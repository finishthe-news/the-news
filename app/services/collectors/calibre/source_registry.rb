require "pathname"
require "uri"
require "yaml"

module Collectors
  module Calibre
    class SourceRegistry
      class InvalidManifest < StandardError; end

      Recipe = Data.define(:type, :id, :path, :resolved_path)
      Discovery = Data.define(
        :feeds,
        :article_hosts,
        :redirect_hosts,
        :update_mode,
        :update_field
      )
      Limits = Data.define(
        :article_cap,
        :timeout_seconds,
        :requests_per_minute,
        :max_concurrency
      )
      PolicyProposal = Data.define(
        :status,
        :access_method,
        :endpoint_url,
        :terms_url,
        :robots_url,
        :retention_days,
        :allowed_uses,
        :attribution,
        :notes
      )
      Manifest = Data.define(
        :version,
        :slug,
        :name,
        :owner_name,
        :source_type,
        :canonical_url,
        :recipe,
        :discovery,
        :limits,
        :policy_proposal,
        :manifest_path
      )

      SOURCE_TYPES = %w[
        primary
        licensed_reporting
        public_reporting
        discovery_only
      ].freeze
      RECIPE_TYPES = %w[builtin generic project].freeze
      UPDATE_MODES = %w[unseen_only trusted_marker].freeze
      UPDATE_FIELDS = %w[feed_updated].freeze
      ACCESS_METHODS = %w[
        public_rss
        public_rss_and_html
        licensed_feed
        public_api
      ].freeze
      ALLOWED_USES = %w[
        discovery
        internal_analysis
        fact_extraction
        quotation_with_attribution
        temporary_storage
      ].freeze

      TOP_LEVEL_KEYS = %w[
        version source recipe discovery limits policy_proposal
      ].freeze
      SOURCE_KEYS = %w[
        slug name owner_name source_type canonical_url
      ].freeze
      RECIPE_KEYS = %w[type id path].freeze
      DISCOVERY_KEYS = %w[feeds allowed_hosts update_strategy].freeze
      FEED_KEYS = %w[url].freeze
      ALLOWED_HOST_KEYS = %w[article redirect].freeze
      UPDATE_STRATEGY_KEYS = %w[mode field].freeze
      LIMIT_KEYS = %w[
        article_cap timeout_seconds requests_per_minute max_concurrency
      ].freeze
      POLICY_KEYS = %w[
        status access_method endpoint_url terms_url robots_url retention_days
        allowed_uses attribution notes
      ].freeze

      SLUG_PATTERN = /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/
      BUILTIN_RECIPE_PATTERN = /\A[a-z0-9][a-z0-9_.-]*\.recipe\z/
      HOST_PATTERN = /\A(?=.{1,253}\z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\z/

      def initialize(
        directory: Rails.root.join("config/news_sources"),
        project_root: Rails.root
      )
        @directory = Pathname(directory).expand_path
        @project_root = Pathname(project_root).expand_path
      end

      def all
        manifests = @directory.glob("*.yml").sort.map { |path| load_file(path) }
        duplicate = manifests.group_by(&:slug).find { |_slug, entries| entries.many? }
        raise InvalidManifest, "duplicate source slug: #{duplicate.first}" if duplicate

        manifests.freeze
      end

      def fetch(slug)
        all.find { |manifest| manifest.slug == slug } || raise(KeyError, slug)
      end

      def load_file(path)
        manifest_path = Pathname(path).expand_path
        document = YAML.safe_load_file(
          manifest_path,
          permitted_classes: [],
          permitted_symbols: [],
          aliases: false
        )
        data = hash!(document, "manifest")
        exact_keys!(data, TOP_LEVEL_KEYS, "manifest")

        version = integer!(data["version"], "version", minimum: 1, maximum: 1)
        source = source!(data.fetch("source"))
        recipe = recipe!(data.fetch("recipe"), source.fetch("slug"))
        discovery = discovery!(data.fetch("discovery"), source.fetch("canonical_url"))
        limits = limits!(data.fetch("limits"))
        policy = policy!(data.fetch("policy_proposal"), discovery.feeds)

        Manifest.new(
          version:,
          slug: source.fetch("slug"),
          name: source.fetch("name"),
          owner_name: source.fetch("owner_name"),
          source_type: source.fetch("source_type"),
          canonical_url: source.fetch("canonical_url"),
          recipe:,
          discovery:,
          limits:,
          policy_proposal: policy,
          manifest_path: manifest_path.to_s
        )
      rescue KeyError => error
        raise InvalidManifest, "#{manifest_path}: missing #{error.key.inspect}"
      rescue Psych::Exception => error
        raise InvalidManifest, "#{manifest_path}: invalid YAML: #{error.message}"
      rescue InvalidManifest => error
        raise InvalidManifest, "#{manifest_path}: #{error.message}"
      end

      private

      def source!(value)
        source = hash!(value, "source")
        exact_keys!(source, SOURCE_KEYS, "source")

        slug = string!(source["slug"], "source.slug")
        invalid!("source.slug must use lower-case kebab-case") unless slug.match?(SLUG_PATTERN)

        source_type = enum!(source["source_type"], SOURCE_TYPES, "source.source_type")
        {
          "slug" => slug,
          "name" => string!(source["name"], "source.name"),
          "owner_name" => string!(source["owner_name"], "source.owner_name"),
          "source_type" => source_type,
          "canonical_url" => http_url!(source["canonical_url"], "source.canonical_url")
        }
      end

      def recipe!(value, slug)
        recipe = hash!(value, "recipe")
        exact_keys!(recipe, RECIPE_KEYS, "recipe", required: %w[type])
        type = enum!(recipe["type"], RECIPE_TYPES, "recipe.type")

        case type
        when "builtin"
          invalid!("recipe.path is not allowed for a builtin recipe") if recipe.key?("path")
          id = string!(recipe["id"], "recipe.id")
          invalid!("recipe.id must be a .recipe filename without directories") unless id.match?(BUILTIN_RECIPE_PATTERN)
          Recipe.new(type:, id:, path: nil, resolved_path: nil)
        when "generic"
          invalid!("recipe.id is not allowed for a generic recipe") if recipe.key?("id")
          invalid!("recipe.path is not allowed for a generic recipe") if recipe.key?("path")
          Recipe.new(type:, id: nil, path: nil, resolved_path: nil)
        when "project"
          invalid!("recipe.id is not allowed for a project recipe") if recipe.key?("id")
          path = string!(recipe["path"], "recipe.path")
          expected_path = "lib/calibre_recipes/#{slug}.recipe"
          invalid!("recipe.path must be #{expected_path.inspect}") unless path == expected_path

          resolved_path = resolve_project_recipe!(path)
          Recipe.new(type:, id: nil, path:, resolved_path: resolved_path.to_s)
        end
      end

      def discovery!(value, canonical_url)
        discovery = hash!(value, "discovery")
        exact_keys!(discovery, DISCOVERY_KEYS, "discovery")

        feeds = array!(discovery["feeds"], "discovery.feeds", minimum: 1, maximum: 20).map.with_index do |entry, index|
          feed = hash!(entry, "discovery.feeds[#{index}]")
          exact_keys!(feed, FEED_KEYS, "discovery.feeds[#{index}]")
          { "url" => http_url!(feed["url"], "discovery.feeds[#{index}].url") }.freeze
        end
        ensure_unique!(feeds.map { |feed| feed.fetch("url") }, "discovery feed URLs")

        allowed_hosts = hash!(discovery["allowed_hosts"], "discovery.allowed_hosts")
        exact_keys!(allowed_hosts, ALLOWED_HOST_KEYS, "discovery.allowed_hosts")
        article_hosts = hosts!(allowed_hosts["article"], "discovery.allowed_hosts.article", minimum: 1)
        redirect_hosts = hosts!(allowed_hosts["redirect"], "discovery.allowed_hosts.redirect", minimum: 0)
        ensure_unique!(article_hosts + redirect_hosts, "allowed hosts")

        canonical_host = URI(canonical_url).host.downcase
        invalid!("source canonical host must be in discovery.allowed_hosts.article") unless article_hosts.include?(canonical_host)

        strategy = hash!(discovery["update_strategy"], "discovery.update_strategy")
        exact_keys!(strategy, UPDATE_STRATEGY_KEYS, "discovery.update_strategy", required: %w[mode])
        mode = enum!(strategy["mode"], UPDATE_MODES, "discovery.update_strategy.mode")
        field = strategy["field"]
        if mode == "unseen_only"
          invalid!("discovery.update_strategy.field is not allowed for unseen_only") if strategy.key?("field")
        else
          field = enum!(field, UPDATE_FIELDS, "discovery.update_strategy.field")
        end

        Discovery.new(
          feeds: feeds.freeze,
          article_hosts: article_hosts.freeze,
          redirect_hosts: redirect_hosts.freeze,
          update_mode: mode,
          update_field: field
        )
      end

      def limits!(value)
        limits = hash!(value, "limits")
        exact_keys!(limits, LIMIT_KEYS, "limits")
        Limits.new(
          article_cap: integer!(limits["article_cap"], "limits.article_cap", minimum: 1, maximum: 500),
          timeout_seconds: integer!(limits["timeout_seconds"], "limits.timeout_seconds", minimum: 1, maximum: 3_600),
          requests_per_minute: integer!(limits["requests_per_minute"], "limits.requests_per_minute", minimum: 1, maximum: 120),
          max_concurrency: integer!(limits["max_concurrency"], "limits.max_concurrency", minimum: 1, maximum: 10)
        )
      end

      def policy!(value, feeds)
        policy = hash!(value, "policy_proposal")
        exact_keys!(policy, POLICY_KEYS, "policy_proposal", required: POLICY_KEYS - %w[notes])
        status = string!(policy["status"], "policy_proposal.status")
        invalid!("policy_proposal.status must be draft") unless status == "draft"

        endpoint_url = http_url!(policy["endpoint_url"], "policy_proposal.endpoint_url")
        invalid!("policy_proposal.endpoint_url must match a discovery feed") unless feeds.any? { |feed| feed.fetch("url") == endpoint_url }

        allowed_uses = array!(policy["allowed_uses"], "policy_proposal.allowed_uses", minimum: 1, maximum: ALLOWED_USES.length).map.with_index do |item, index|
          enum!(item, ALLOWED_USES, "policy_proposal.allowed_uses[#{index}]")
        end
        ensure_unique!(allowed_uses, "policy_proposal.allowed_uses")

        PolicyProposal.new(
          status:,
          access_method: enum!(policy["access_method"], ACCESS_METHODS, "policy_proposal.access_method"),
          endpoint_url:,
          terms_url: http_url!(policy["terms_url"], "policy_proposal.terms_url"),
          robots_url: http_url!(policy["robots_url"], "policy_proposal.robots_url"),
          retention_days: integer!(policy["retention_days"], "policy_proposal.retention_days", minimum: 0, maximum: 365),
          allowed_uses: allowed_uses.freeze,
          attribution: string!(policy["attribution"], "policy_proposal.attribution"),
          notes: policy.key?("notes") ? string!(policy["notes"], "policy_proposal.notes") : nil
        )
      end

      def resolve_project_recipe!(path)
        recipe_root = @project_root.join("lib/calibre_recipes").expand_path
        candidate = @project_root.join(path).expand_path
        unless candidate.to_s.start_with?("#{recipe_root}#{File::SEPARATOR}")
          invalid!("recipe.path escapes lib/calibre_recipes")
        end
        invalid!("project recipe does not exist: #{path}") unless candidate.file?

        real_root = recipe_root.realpath
        real_candidate = candidate.realpath
        unless real_candidate.to_s.start_with?("#{real_root}#{File::SEPARATOR}")
          invalid!("recipe.path resolves outside lib/calibre_recipes")
        end

        real_candidate
      end

      def exact_keys!(hash, allowed, location, required: allowed)
        unknown = hash.keys - allowed
        missing = required - hash.keys
        invalid!("#{location} has unknown keys: #{unknown.join(', ')}") if unknown.any?
        invalid!("#{location} is missing keys: #{missing.join(', ')}") if missing.any?
      end

      def hash!(value, location)
        invalid!("#{location} must be a mapping") unless value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) }
        value
      end

      def array!(value, location, minimum:, maximum:)
        invalid!("#{location} must be an array") unless value.is_a?(Array)
        invalid!("#{location} must contain between #{minimum} and #{maximum} items") unless value.length.between?(minimum, maximum)
        value
      end

      def string!(value, location)
        invalid!("#{location} must be a non-empty string") unless value.is_a?(String) && value.strip == value && value.present?
        value
      end

      def integer!(value, location, minimum:, maximum:)
        invalid!("#{location} must be an integer from #{minimum} through #{maximum}") unless value.is_a?(Integer) && value.between?(minimum, maximum)
        value
      end

      def enum!(value, values, location)
        invalid!("#{location} must be one of: #{values.join(', ')}") unless values.include?(value)
        value
      end

      def http_url!(value, location)
        url = string!(value, location)
        uri = URI.parse(url)
        valid = uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
        invalid!("#{location} must be an HTTP(S) URL without credentials") unless valid
        url
      rescue URI::InvalidURIError
        invalid!("#{location} must be a valid HTTP(S) URL")
      end

      def hosts!(value, location, minimum:)
        hosts = array!(value, location, minimum:, maximum: 50).map.with_index do |host, index|
          host = string!(host, "#{location}[#{index}]")
          invalid!("#{location}[#{index}] must be a lower-case hostname") unless host.match?(HOST_PATTERN)
          host
        end
        ensure_unique!(hosts, location)
        hosts
      end

      def ensure_unique!(values, location)
        invalid!("#{location} contains duplicates") unless values.uniq.length == values.length
      end

      def invalid!(message)
        raise InvalidManifest, message
      end
    end
  end
end
