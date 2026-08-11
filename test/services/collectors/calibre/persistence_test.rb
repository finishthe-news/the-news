require "test_helper"
require "tmpdir"

class Collectors::Calibre::PersistenceTest < ActiveSupport::TestCase
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
      access_method: "public_rss_and_article_pages",
      endpoint_url: "https://news.example.test/feed.xml",
      reviewed_by: "Test editor",
      reviewed_at: Time.current,
      content_hash: SecureRandom.hex(32)
    )
    @run_root = Dir.mktmpdir("calibre-persistence-test")
  end

  teardown do
    FileUtils.remove_entry(@run_root)
  end

  test "persists distinct publisher dates and an immutable title plus body snapshot" do
    result = persister(collection_run).call(
      records: [ article_record ],
      observations: [ discovery_record ]
    )

    assert_equal 1, result.documents_seen
    assert_equal 1, result.documents_created
    assert_equal 1, result.snapshots_created
    assert_equal 1, result.observations_created
    assert_empty result.errors

    document = @source.source_documents.sole
    assert_equal Time.zone.parse("2026-08-11T09:00:00-04:00"), document.published_at
    assert_equal Time.zone.parse("2026-08-11T10:30:00-04:00"), document.source_updated_at
    assert_equal Time.zone.parse("2026-08-11T10:25:00-04:00"), document.discovery_updated_at
    assert_equal "2026-08-11T09:00:00-04:00",
      document.metadata.dig("date_provenance", "article_published", "raw_value")
    assert_equal "article_markup",
      document.metadata.dig("date_provenance", "article_updated", "method")

    snapshot = document.document_snapshots.sole
    assert_equal "Synthetic headline", snapshot.payload.dig("article", "title")
    assert_equal "A synthetic first paragraph.\n\nA second paragraph.",
      snapshot.payload.dig("content", "body_text")
    assert_equal true, snapshot.payload.dig("acquisition", "http_receipt_inferred")
    assert_not snapshot.update(payload: {})
  end

  test "normalized whitespace creates no duplicate snapshot and a title change does" do
    first_run = collection_run
    first = persister(first_run).call(records: [ article_record ], observations: [])
    assert_equal 1, first.snapshots_created

    File.write(body_path, " A   synthetic first paragraph.\r\n\r\n\r\nA second paragraph. ")
    second = persister(collection_run).call(records: [ article_record ], observations: [])
    assert_equal 0, second.snapshots_created

    changed = article_record.merge("title" => "Corrected synthetic headline")
    third = persister(collection_run).call(records: [ changed ], observations: [])
    assert_equal 1, third.snapshots_created
    assert_equal 2, @source.source_documents.sole.document_snapshots.count
  end

  test "one malformed article does not discard a valid article" do
    invalid = article_record.merge("canonical_url" => "not a URL")
    result = persister(collection_run).call(
      records: [ invalid, article_record ],
      observations: []
    )

    assert_equal 2, result.documents_seen
    assert_equal 1, result.documents_created
    assert_equal 1, result.snapshots_created
    assert_equal 1, result.errors.length
    assert_equal "article", result.errors.first.fetch("kind")
  end

  test "rejects a body path outside the ignored run directory" do
    outside = Tempfile.new("outside-calibre-body")
    outside.write("Synthetic text")
    outside.close
    record = article_record.merge("body_text_path" => outside.path)

    error = assert_raises(Collectors::Calibre::Normalizer::InvalidRecord) do
      normalizer.call(record)
    end
    assert_equal "body_text_path is outside the run root", error.message
  ensure
    outside&.unlink
  end

  test "rejects non ISO date text instead of guessing a timestamp" do
    malformed = article_record.deep_merge(
      "dates" => { "feed_published" => "time.struct_time(tm_year=2026, tm_mon=8)" }
    )

    error = assert_raises(Collectors::Calibre::Normalizer::InvalidRecord) do
      normalizer.call(malformed)
    end

    assert_equal "dates.feed_published is not a valid time", error.message
  end

  test "known state exports only persisted documents in canonical URL order" do
    persister(collection_run).call(records: [ article_record ], observations: [])

    state = Collectors::Calibre::KnownState.new(source: @source).as_json

    assert_equal "calibre-known-state/v1", state.fetch("schema_version")
    assert_equal "synthetic-news", state.fetch("source_slug")
    assert_equal [ {
      "canonical_url" => "https://news.example.test/articles/example",
      "source_updated_at" => "2026-08-11T14:25:00Z"
    } ], state.fetch("documents")
  end

  test "rejects article receipts from hosts outside the source manifest" do
    record = article_record.merge("canonical_url" => "https://other.test/articles/example")

    error = assert_raises(Collectors::Calibre::Normalizer::InvalidRecord) do
      normalizer.call(record)
    end

    assert_equal "canonical_url host is not allowed", error.message
  end

  test "records an invalid discovery candidate without treating it as known state" do
    invalid = discovery_record.merge(
      "canonical_url" => nil,
      "decision" => "skip",
      "reason" => "invalid_url"
    )
    result = persister(collection_run).call(records: [], observations: [ invalid ])

    assert_equal 1, result.observations_created
    observation = @source.discovery_observations.sole
    assert_nil observation.canonical_url
    assert_equal "invalid_url", observation.metadata.fetch("reason")
    assert_equal Time.zone.parse("2026-08-11T08:55:00-04:00"), observation.published_at
    assert_equal Time.zone.parse("2026-08-11T10:25:00-04:00"), observation.source_updated_at
    assert_equal "2026-08-11T08:55:00-04:00",
      observation.metadata.dig("date_provenance", "feed_published", "raw_value")
    assert_empty Collectors::Calibre::KnownState.new(source: @source).as_json.fetch("documents")
    assert_not observation.update(observed_at: 1.hour.from_now)
  end

  test "rejects non ISO discovery dates instead of guessing a timestamp" do
    malformed = discovery_record.merge(
      "feed_published" => "time.struct_time(tm_year=2026, tm_mon=8)"
    )

    result = persister(collection_run).call(records: [], observations: [ malformed ])

    assert_equal 0, result.observations_created
    assert_equal 1, result.errors.length
    assert_equal "discovery date is not a valid time", result.errors.first.fetch("error_message")
  end

  test "news collection slots permit only one claim per source and hour" do
    slot_at = Time.zone.parse("2026-08-11 12:00:00")
    now = Time.zone.parse("2026-08-11 12:05:00")
    slot = NewsCollectionSlot.claim(source: @source, slot_at:, now:)

    assert_nil NewsCollectionSlot.claim(source: @source, slot_at:, now: now + 10.minutes)
    reclaimed = NewsCollectionSlot.claim(source: @source, slot_at:, now: now + 61.minutes)
    assert_equal slot, reclaimed
    assert_equal 2, reclaimed.attempts

    next_hour = NewsCollectionSlot.claim(
      source: @source,
      slot_at: slot_at + 1.hour,
      now: now + 61.minutes
    )
    assert_nil next_hour

    run = collection_run
    reclaimed.succeed!(collection_run: run, now: now + 62.minutes)
    assert reclaimed.status_succeeded?
    assert_equal run, reclaimed.collection_run
    assert_nil NewsCollectionSlot.claim(source: @source, slot_at:, now: now + 2.hours)

    assert_not NewsCollectionSlot.new(
      source: @source,
      slot_at: slot_at + 1.minute,
      claimed_at: now,
      lease_expires_at: now + 1.hour
    ).valid?
  end

  test "a retry can attach a pre-cycle failed slot to its coordinator receipt" do
    slot_at = Time.zone.parse("2026-08-11 12:00:00")
    now = Time.zone.parse("2026-08-11 12:05:00")
    slot = NewsCollectionSlot.claim(source: @source, slot_at:, now:)
    slot.fail!(now: now + 1.minute)
    cycle, = NewsCollectionCycle.begin!(slot_at:, source_slugs: [ @source.slug ], now:)

    retried = NewsCollectionSlot.claim(
      source: @source,
      slot_at:,
      cycle:,
      now: now + 2.minutes
    )

    assert_equal slot, retried
    assert_equal cycle, retried.news_collection_cycle
    assert_equal 2, retried.attempts
  end

  private

  def persister(run)
    Collectors::Calibre::Persister.new(
      source: @source,
      policy: @policy,
      collection_run: run,
      run_root: @run_root,
      allowed_hosts: [ "news.example.test" ],
      clock: -> { Time.zone.parse("2026-08-11T15:00:00Z") },
      collector_identity: "TheNews/test"
    )
  end

  def normalizer
    Collectors::Calibre::Normalizer.new(
      source: @source,
      run_root: @run_root,
      allowed_hosts: [ "news.example.test" ]
    )
  end

  def collection_run
    @source.collection_runs.create!(
      source_policy: @policy,
      adapter_name: "calibre",
      adapter_version: "1",
      started_at: Time.zone.parse("2026-08-11T15:00:00Z")
    )
  end

  def body_path
    path = File.join(@run_root, "article.txt")
    File.write(path, "A synthetic first paragraph.\n\nA second paragraph.") unless File.exist?(path)
    path
  end

  def article_record
    {
      "schema_version" => "calibre-article/v1",
      "source_slug" => "synthetic-news",
      "canonical_url" => "https://news.example.test/articles/example",
      "requested_url" => "https://news.example.test/go/example",
      "title" => "  Synthetic   headline ",
      "authors" => [ "Test Reporter" ],
      "language" => "en",
      "section" => "United States",
      "description" => "Synthetic description",
      "dates" => {
        "feed_published" => "2026-08-11T08:55:00-04:00",
        "feed_updated" => "2026-08-11T10:25:00-04:00",
        "article_published" => "2026-08-11T09:00:00-04:00",
        "article_updated" => "2026-08-11T10:30:00-04:00"
      },
      "body_text_path" => body_path,
      "word_count" => 7,
      "content_hash" => "0" * 64,
      "acquisition" => {
        "retrieved_at" => "2026-08-11T15:00:00Z",
        "collector" => "calibre",
        "recipe_path" => "builtin:synthetic.recipe"
      }
    }
  end

  def discovery_record
    {
      "schema_version" => "calibre-discovery-decision/v1",
      "source_slug" => "synthetic-news",
      "hook" => "parse_feeds",
      "discovered_url" => "https://news.example.test/go/example",
      "canonical_url" => "https://news.example.test/articles/example",
      "title" => "Synthetic headline",
      "source_updated_at" => "2026-08-11T10:30:00-04:00",
      "feed_published" => "2026-08-11T08:55:00-04:00",
      "feed_updated" => "2026-08-11T10:25:00-04:00",
      "known_source_updated_at" => nil,
      "decision" => "fetch",
      "reason" => "unseen"
    }
  end
end
