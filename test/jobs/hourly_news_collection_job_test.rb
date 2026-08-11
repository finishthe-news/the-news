require "test_helper"

class HourlyNewsCollectionJobTest < ActiveJob::TestCase
  include ActiveJob::TestHelper

  test "enqueues only active sources with approved policies" do
    approved = create_source("pbs-newshour", active: true, approved: true)
    create_source("the-marshall-project", active: true, approved: false)
    create_source("abc-news", active: false, approved: true)

    assert_enqueued_jobs 1, only: NewsSourceCollectionJob do
      HourlyNewsCollectionJob.perform_now(
        slot_at: Time.zone.parse("2026-08-11T10:42:00Z")
      )
    end

    job = enqueued_jobs.find { |entry| entry.fetch(:job) == NewsSourceCollectionJob }
    assert_equal approved.slug, job.fetch(:args).first
    assert_includes job.fetch(:args).to_s, "2026-08-11T10:00:00Z"
  end

  test "a source job records a successful terminal slot" do
    source = create_source("pbs-newshour", active: true, approved: true)
    manifest = Collectors::Calibre::SourceRegistry.new.fetch(source.slug)
    run = source.collection_runs.create!(
      source_policy: source.approved_policy,
      adapter_name: "calibre",
      adapter_version: "1",
      started_at: Time.current,
      status: "succeeded",
      finished_at: Time.current
    )
    fake_collector = Object.new
    fake_collector.define_singleton_method(:call) { run }

    job = NewsSourceCollectionJob.new
    job.define_singleton_method(:collector_for) do |source:, manifest:|
      fake_collector
    end
    job.send(:perform, source.slug, slot_at: "2026-08-11T10:00:00Z")

    slot = source.news_collection_slots.sole
    assert slot.status_succeeded?
    assert_equal run, slot.collection_run
    assert_equal manifest.limits.timeout_seconds.seconds + 5.minutes,
      slot.lease_expires_at - slot.claimed_at
  end

  private

  def create_source(slug, active:, approved:)
    source = Source.create!(
      slug:,
      name: slug.titleize,
      owner_name: "Test Publisher",
      source_type: "public_reporting",
      canonical_url: "https://#{slug}.example.test/",
      active:
    )
    source.source_policies.create!(
      version: 1,
      status: approved ? "approved" : "draft",
      access_method: "public_rss_and_html",
      endpoint_url: "https://#{slug}.example.test/feed.xml",
      reviewed_by: approved ? "Test editor" : nil,
      reviewed_at: approved ? Time.current : nil,
      content_hash: SecureRandom.hex(32)
    )
    source
  end
end
