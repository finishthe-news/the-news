module Collectors
  module Calibre
    class SourceSynchronizer
      Result = Data.define(:source, :policy, :policy_created)

      def initialize(registry: SourceRegistry.new)
        @registry = registry
      end

      def call
        @registry.all.map { |manifest| sync(manifest) }
      end

      def sync(manifest)
        source = Source.find_or_initialize_by(slug: manifest.slug)
        source.assign_attributes(
          name: manifest.name,
          owner_name: manifest.owner_name,
          source_type: manifest.source_type,
          canonical_url: manifest.canonical_url
        )
        source.save!

        attributes = policy_attributes(manifest)
        content_hash = CanonicalJson.sha256(attributes)
        policy = source.source_policies.find_by(content_hash:)
        return Result.new(source:, policy:, policy_created: false) if policy

        policy = source.source_policies.create!(
          attributes.merge(
            version: source.source_policies.maximum(:version).to_i + 1,
            status: "draft",
            content_hash:
          )
        )
        Result.new(source:, policy:, policy_created: true)
      end

      private

      def policy_attributes(manifest)
        proposal = manifest.policy_proposal
        {
          access_method: proposal.access_method,
          endpoint_url: proposal.endpoint_url,
          terms_url: proposal.terms_url,
          robots_url: proposal.robots_url,
          requests_per_minute: manifest.limits.requests_per_minute,
          max_concurrency: manifest.limits.max_concurrency,
          retention_days: proposal.retention_days,
          allowed_uses: proposal.allowed_uses,
          attribution_requirements: proposal.attribution,
          notes: proposal.notes
        }
      end
    end
  end
end
