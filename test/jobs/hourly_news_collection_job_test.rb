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
    cycle = NewsCollectionCycle.sole
    assert cycle.status_running?
    assert_equal [ approved.slug ], cycle.expected_source_slugs
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
    cycle, = NewsCollectionCycle.begin!(
      slot_at: Time.zone.parse("2026-08-11T10:00:00Z"),
      source_slugs: [ source.slug ]
    )
    cycle.mark_running!
    job.send(
      :perform,
      source.slug,
      slot_at: "2026-08-11T10:00:00Z",
      cycle_id: cycle.id
    )

    slot = source.news_collection_slots.sole
    assert slot.status_succeeded?
    assert_equal run, slot.collection_run
    assert_equal manifest.limits.timeout_seconds.seconds + 5.minutes,
      slot.lease_expires_at - slot.claimed_at
    assert cycle.reload.status_completed?
  end

  test "records an empty coordinator cycle as completed" do
    cycle = HourlyNewsCollectionJob.perform_now(
      slot_at: Time.zone.parse("2026-08-11T11:42:00Z")
    )

    assert cycle.status_completed?
    assert_empty cycle.expected_source_slugs
    assert_equal Time.zone.parse("2026-08-11T11:00:00Z"), cycle.slot_at
  end

  test "does not redispatch an already recorded hour" do
    create_source("pbs-newshour", active: true, approved: true)

    assert_enqueued_jobs 1, only: NewsSourceCollectionJob do
      2.times do
        HourlyNewsCollectionJob.perform_now(
          slot_at: Time.zone.parse("2026-08-11T12:42:00Z")
        )
      end
    end
    assert_equal 1, NewsCollectionCycle.count
  end

  test "one source failure does not prevent another source receipt" do
    failed_source = create_source("pbs-newshour", active: true, approved: true)
    successful_source = create_source("the-marshall-project", active: true, approved: true)
    slot_at = Time.zone.parse("2026-08-11T13:00:00Z")
    cycle, = NewsCollectionCycle.begin!(
      slot_at:,
      source_slugs: [ failed_source.slug, successful_source.slug ]
    )
    cycle.mark_running!

    failed_run = collection_run(failed_source, status: "failed")
    failure = Collectors::Calibre::Collector::CollectionFailure.new(
      "synthetic failure",
      collection_run: failed_run
    )
    perform_source_job(failed_source, cycle:, slot_at:) { raise failure }

    successful_run = collection_run(successful_source, status: "succeeded")
    perform_source_job(successful_source, cycle:, slot_at:) { successful_run }

    assert_equal %w[failed succeeded], cycle.news_collection_slots.order(:source_id).pluck(:status).sort
    assert cycle.reload.status_completed?
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

  def collection_run(source, status:)
    source.collection_runs.create!(
      source_policy: source.approved_policy,
      adapter_name: "calibre",
      adapter_version: "1",
      started_at: Time.current,
      status:,
      finished_at: Time.current
    )
  end

  def perform_source_job(source, cycle:, slot_at:, &collector_call)
    collector = Object.new
    collector.define_singleton_method(:call, &collector_call)
    job = NewsSourceCollectionJob.new
    job.define_singleton_method(:collector_for) { |**| collector }
    job.send(
      :perform,
      source.slug,
      slot_at: slot_at.iso8601,
      cycle_id: cycle.id
    )
  rescue Collectors::Calibre::Collector::CollectionFailure
    nil
  end
end
