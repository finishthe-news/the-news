require "test_helper"
require "tmpdir"

class Collectors::Calibre::CollectorTest < ActiveSupport::TestCase
  setup do
    @source = Source.create!(
      name: "Synthetic News",
      slug: "synthetic-news",
      source_type: "public_reporting",
      owner_name: "Synthetic Publisher",
      canonical_url: "https://news.example.test/",
      active: true
    )
    @policy = @source.source_policies.create!(
      version: 1,
      status: "approved",
      access_method: "public_rss_and_html",
      endpoint_url: "https://news.example.test/feed.xml",
      reviewed_by: "Test editor",
      reviewed_at: Time.current,
      content_hash: SecureRandom.hex(32)
    )
    @run_parent = Pathname(Dir.mktmpdir("collector-test"))
  end

  teardown do
    FileUtils.remove_entry(@run_parent)
  end

  test "completes a collection run and stores bridge receipts" do
    runner = SuccessfulRunner.new

    run = collector(runner).call

    assert run.status_succeeded?
    assert_equal 1, run.documents_seen
    assert_equal 1, run.documents_created
    assert_equal 1, run.snapshots_created
    assert_equal "succeeded", run.metadata.dig("calibre", "outcome")
    assert_equal 1, @source.source_documents.count
    assert_equal 1, @source.discovery_observations.count
    assert_equal [], runner.known_states.first.fetch("documents")
  end

  test "marks the run failed while retaining discovery receipts" do
    runner = SuccessfulRunner.new(outcome: "failed", exit_status: 1, records: false)

    error = assert_raises(Collectors::Calibre::Collector::CollectionFailure) do
      collector(runner).call
    end

    assert_equal "Calibre bridge outcome was failed", error.message
    assert error.collection_run.status_failed?
    assert_equal 1, @source.discovery_observations.count
  end

  test "refuses an inactive source even when it has an approved policy" do
    @source.update!(active: false)

    assert_raises(ArgumentError) { collector(SuccessfulRunner.new).call }
    assert_empty @source.collection_runs
  end

  test "validates collector identity before invoking Calibre" do
    runner = Object.new
    runner.define_singleton_method(:call) { |**| flunk("Calibre must not run without a collector identity") }
    collector = Collectors::Calibre::Collector.new(
      source: @source,
      manifest: manifest,
      runner:,
      collector_identity: -> { raise Collectors::CollectorIdentity::MissingContact, "missing" },
      run_parent: @run_parent
    )

    assert_raises(Collectors::CollectorIdentity::MissingContact) { collector.call }
    assert_empty @source.collection_runs
  end

  private

  def collector(runner)
    Collectors::Calibre::Collector.new(
      source: @source,
      manifest: manifest,
      runner:,
      run_parent: @run_parent
    )
  end

  def manifest
    registry = Collectors::Calibre::SourceRegistry
    registry::Manifest.new(
      version: 1,
      slug: "synthetic-news",
      name: "Synthetic News",
      owner_name: "Synthetic Publisher",
      source_type: "public_reporting",
      canonical_url: "https://news.example.test/",
      recipe: registry::Recipe.new(type: "generic", id: nil, path: nil, resolved_path: nil),
      discovery: registry::Discovery.new(
        feeds: [ { "url" => "https://news.example.test/feed.xml" } ],
        article_hosts: [ "news.example.test" ],
        redirect_hosts: [],
        update_mode: "unseen_only",
        update_field: nil
      ),
      limits: registry::Limits.new(
        article_cap: 10,
        timeout_seconds: 60,
        requests_per_minute: 10,
        max_concurrency: 1
      ),
      policy_proposal: nil,
      manifest_path: "/app/synthetic.yml"
    )
  end

  class SuccessfulRunner
    attr_reader :known_states

    def initialize(outcome: "succeeded", exit_status: 0, records: true)
      @outcome = outcome
      @exit_status = exit_status
      @records = records
      @known_states = []
    end

    def call(manifest:, known_state:, run_root:)
      @known_states << known_state
      body = Pathname(run_root).join("article.txt")
      body.write("A synthetic article body with enough information for testing.")
      records = @records ? [ article_record(body) ] : []
      process = Collectors::Calibre::RecipeRunner::ProcessResult.new(
        stdout: "", stderr: "", exit_status: @exit_status
      )
      Collectors::Calibre::RecipeRunner::Result.new(
        records:,
        observations: [ discovery_record ],
        report: {
          "outcome" => @outcome,
          "elapsed_seconds" => 0.1,
          "calibre_exit_code" => @exit_status,
          "counts" => { "discovered" => 1, "eligible" => records.length, "normalized" => records.length },
          "instrumentation" => {}
        },
        process_result: process
      )
    end

    private

    def article_record(body)
      {
        "schema_version" => "calibre-article/v1",
        "source_slug" => "synthetic-news",
        "canonical_url" => "https://news.example.test/story",
        "requested_url" => "https://news.example.test/story",
        "title" => "Synthetic story",
        "authors" => [ "Reporter" ],
        "language" => "en",
        "section" => "United States",
        "description" => "Test story",
        "dates" => {
          "feed_published" => "2026-08-11T10:00:00Z",
          "feed_updated" => nil,
          "article_published" => nil,
          "article_updated" => nil
        },
        "body_text_path" => body.to_s,
        "word_count" => 9,
        "content_hash" => "0" * 64,
        "acquisition" => {
          "retrieved_at" => "2026-08-11T11:00:00Z",
          "collector" => "calibre",
          "recipe_path" => "generated:generic"
        }
      }
    end

    def discovery_record
      {
        "schema_version" => "calibre-discovery-decision/v1",
        "source_slug" => "synthetic-news",
        "hook" => "parse_feeds",
        "discovered_url" => "https://news.example.test/story",
        "canonical_url" => "https://news.example.test/story",
        "title" => "Synthetic story",
        "feed_published" => "2026-08-11T10:00:00Z",
        "feed_updated" => nil,
        "source_updated_at" => nil,
        "known_source_updated_at" => nil,
        "decision" => "fetch",
        "reason" => "unseen"
      }
    end
  end
end
