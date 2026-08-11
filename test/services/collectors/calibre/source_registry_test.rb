require "test_helper"
require "fileutils"
require "tmpdir"

class Collectors::Calibre::SourceRegistryTest < ActiveSupport::TestCase
  def setup
    @root = Pathname(Dir.mktmpdir("source-registry"))
    @directory = @root.join("config/news_sources")
    @directory.mkpath
    @registry = Collectors::Calibre::SourceRegistry.new(
      directory: @directory,
      project_root: @root
    )
  end

  def teardown
    FileUtils.remove_entry(@root) if @root&.exist?
  end

  test "loads the complete builtin recipe contract" do
    path = write_manifest(valid_manifest)

    manifest = @registry.load_file(path)

    assert_equal 1, manifest.version
    assert_equal "example-news", manifest.slug
    assert_equal "public_reporting", manifest.source_type
    assert_equal "builtin", manifest.recipe.type
    assert_equal "example_news.recipe", manifest.recipe.id
    assert_nil manifest.recipe.path
    assert_equal [ { "url" => "https://www.example.com/news.rss" } ], manifest.discovery.feeds
    assert_equal [ "www.example.com" ], manifest.discovery.article_hosts
    assert_equal "unseen_only", manifest.discovery.update_mode
    assert_nil manifest.discovery.update_field
    assert_equal 100, manifest.limits.article_cap
    assert_equal "draft", manifest.policy_proposal.status
    assert_equal [ "discovery", "internal_analysis", "fact_extraction" ], manifest.policy_proposal.allowed_uses
  end

  test "loads a trusted marker and a source-scoped project recipe" do
    recipe = @root.join("lib/calibre_recipes/example-news.recipe")
    recipe.dirname.mkpath
    recipe.write("# synthetic recipe\n")
    data = valid_manifest
    data["recipe"] = {
      "type" => "project",
      "path" => "lib/calibre_recipes/example-news.recipe"
    }
    data["discovery"]["update_strategy"] = {
      "mode" => "trusted_marker",
      "field" => "feed_updated"
    }

    manifest = @registry.load_file(write_manifest(data))

    assert_equal "project", manifest.recipe.type
    assert_equal recipe.realpath.to_s, manifest.recipe.resolved_path
    assert_equal "feed_updated", manifest.discovery.update_field
  end

  test "loads a feed-driven generic recipe without an id or path" do
    data = valid_manifest
    data["recipe"] = { "type" => "generic" }

    manifest = @registry.load_file(write_manifest(data))

    assert_equal "generic", manifest.recipe.type
    assert_nil manifest.recipe.id
    assert_nil manifest.recipe.path
    assert_nil manifest.recipe.resolved_path
  end

  test "rejects an id or path on a generic recipe" do
    data = valid_manifest
    data["recipe"] = { "type" => "generic", "id" => "example_news.recipe" }

    id_error = assert_raises(Collectors::Calibre::SourceRegistry::InvalidManifest) do
      @registry.load_file(write_manifest(data))
    end
    assert_includes id_error.message, "recipe.id is not allowed for a generic recipe"

    data["recipe"] = { "type" => "generic", "path" => "lib/calibre_recipes/example-news.recipe" }
    path_error = assert_raises(Collectors::Calibre::SourceRegistry::InvalidManifest) do
      @registry.load_file(write_manifest(data))
    end
    assert_includes path_error.message, "recipe.path is not allowed for a generic recipe"
  end

  test "rejects unknown keys at every contract boundary" do
    data = valid_manifest
    data["limits"]["retry_count"] = 3

    error = assert_raises(Collectors::Calibre::SourceRegistry::InvalidManifest) do
      @registry.load_file(write_manifest(data))
    end

    assert_includes error.message, "limits has unknown keys: retry_count"
  end

  test "rejects a policy proposal that attempts to approve itself" do
    data = valid_manifest
    data["policy_proposal"]["status"] = "approved"

    error = assert_raises(Collectors::Calibre::SourceRegistry::InvalidManifest) do
      @registry.load_file(write_manifest(data))
    end

    assert_includes error.message, "policy_proposal.status must be draft"
  end

  test "rejects an update field for unseen-only collection" do
    data = valid_manifest
    data["discovery"]["update_strategy"]["field"] = "feed_updated"

    error = assert_raises(Collectors::Calibre::SourceRegistry::InvalidManifest) do
      @registry.load_file(write_manifest(data))
    end

    assert_includes error.message, "field is not allowed for unseen_only"
  end

  test "rejects path traversal and missing project recipes" do
    data = valid_manifest
    data["recipe"] = {
      "type" => "project",
      "path" => "../../outside.recipe"
    }

    traversal_error = assert_raises(Collectors::Calibre::SourceRegistry::InvalidManifest) do
      @registry.load_file(write_manifest(data))
    end
    assert_includes traversal_error.message, "recipe.path must be"

    data["recipe"]["path"] = "lib/calibre_recipes/example-news.recipe"
    missing_error = assert_raises(Collectors::Calibre::SourceRegistry::InvalidManifest) do
      @registry.load_file(write_manifest(data))
    end
    assert_includes missing_error.message, "project recipe does not exist"
  end

  test "rejects a symlinked project recipe outside the recipe directory" do
    outside = @root.join("outside.recipe")
    outside.write("# outside\n")
    recipe = @root.join("lib/calibre_recipes/example-news.recipe")
    recipe.dirname.mkpath
    FileUtils.ln_s(outside, recipe)
    data = valid_manifest
    data["recipe"] = {
      "type" => "project",
      "path" => "lib/calibre_recipes/example-news.recipe"
    }

    error = assert_raises(Collectors::Calibre::SourceRegistry::InvalidManifest) do
      @registry.load_file(write_manifest(data))
    end

    assert_includes error.message, "resolves outside lib/calibre_recipes"
  end

  test "rejects hosts that are not explicit lower-case hostnames" do
    data = valid_manifest
    data["discovery"]["allowed_hosts"]["redirect"] = [ "*.example.com" ]

    error = assert_raises(Collectors::Calibre::SourceRegistry::InvalidManifest) do
      @registry.load_file(write_manifest(data))
    end

    assert_includes error.message, "must be a lower-case hostname"
  end

  test "rejects duplicate source slugs across files" do
    write_manifest(valid_manifest, "one.yml")
    write_manifest(valid_manifest, "two.yml")

    error = assert_raises(Collectors::Calibre::SourceRegistry::InvalidManifest) do
      @registry.all
    end

    assert_equal "duplicate source slug: example-news", error.message
  end

  test "example manifest stays synchronized with the executable contract" do
    example = Rails.root.join("config/news_sources/manifest.yml.example")

    manifest = @registry.load_file(example)

    assert_equal "example-news", manifest.slug
    assert_equal "generic", manifest.recipe.type
    assert_equal "draft", manifest.policy_proposal.status
  end

  private

  def write_manifest(data, filename = "example-news.yml")
    path = @directory.join(filename)
    path.write(YAML.dump(data))
    path
  end

  def valid_manifest
    {
      "version" => 1,
      "source" => {
        "slug" => "example-news",
        "name" => "Example News",
        "owner_name" => "Example News Cooperative",
        "source_type" => "public_reporting",
        "canonical_url" => "https://www.example.com/"
      },
      "recipe" => {
        "type" => "builtin",
        "id" => "example_news.recipe"
      },
      "discovery" => {
        "feeds" => [
          { "url" => "https://www.example.com/news.rss" }
        ],
        "allowed_hosts" => {
          "article" => [ "www.example.com" ],
          "redirect" => []
        },
        "update_strategy" => {
          "mode" => "unseen_only"
        }
      },
      "limits" => {
        "article_cap" => 100,
        "timeout_seconds" => 900,
        "requests_per_minute" => 10,
        "max_concurrency" => 1
      },
      "policy_proposal" => {
        "status" => "draft",
        "access_method" => "public_rss_and_html",
        "endpoint_url" => "https://www.example.com/news.rss",
        "terms_url" => "https://www.example.com/terms",
        "robots_url" => "https://www.example.com/robots.txt",
        "retention_days" => 30,
        "allowed_uses" => [ "discovery", "internal_analysis", "fact_extraction" ],
        "attribution" => "Credit and link Example News when its reporting supports a claim.",
        "notes" => "Synthetic test manifest."
      }
    }
  end
end
