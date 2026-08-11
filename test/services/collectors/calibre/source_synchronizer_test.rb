require "test_helper"

class Collectors::Calibre::SourceSynchronizerTest < ActiveSupport::TestCase
  test "creates an inactive source and a draft policy without approving it" do
    result = synchronizer.sync(manifest)

    assert_not result.source.active?
    assert result.policy.status_draft?
    assert result.policy_created
    assert_equal 6, result.policy.requests_per_minute
    assert_equal [ "discovery", "internal_analysis" ], result.policy.allowed_uses
    assert_nil result.policy.reviewed_by
  end

  test "is idempotent for unchanged policy content" do
    first = synchronizer.sync(manifest)
    second = synchronizer.sync(manifest)

    assert_not second.policy_created
    assert_equal first.policy, second.policy
    assert_equal 1, second.source.source_policies.count
  end

  test "does not deactivate an already active source" do
    source = Source.create!(
      slug: "example-news",
      name: "Old name",
      owner_name: "Publisher",
      source_type: "public_reporting",
      canonical_url: "https://example.test/",
      active: true
    )

    result = synchronizer.sync(manifest)

    assert_equal source, result.source
    assert result.source.active?
    assert_equal "Example News", result.source.name
  end

  private

  def synchronizer
    Collectors::Calibre::SourceSynchronizer.new
  end

  def manifest
    registry = Collectors::Calibre::SourceRegistry
    registry::Manifest.new(
      version: 1,
      slug: "example-news",
      name: "Example News",
      owner_name: "Publisher",
      source_type: "public_reporting",
      canonical_url: "https://example.test/",
      recipe: registry::Recipe.new(type: "generic", id: nil, path: nil, resolved_path: nil),
      discovery: registry::Discovery.new(
        feeds: [ { "url" => "https://example.test/feed.xml" } ],
        article_hosts: [ "example.test" ],
        redirect_hosts: [],
        update_mode: "unseen_only",
        update_field: nil
      ),
      limits: registry::Limits.new(
        article_cap: 10,
        timeout_seconds: 600,
        requests_per_minute: 6,
        max_concurrency: 1
      ),
      policy_proposal: registry::PolicyProposal.new(
        status: "draft",
        access_method: "public_rss_and_html",
        endpoint_url: "https://example.test/feed.xml",
        terms_url: "https://example.test/terms",
        robots_url: "https://example.test/robots.txt",
        retention_days: 30,
        allowed_uses: [ "discovery", "internal_analysis" ],
        attribution: "Credit Example News.",
        notes: "Synthetic."
      ),
      manifest_path: "/app/example.yml"
    )
  end
end
