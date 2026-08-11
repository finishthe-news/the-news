require "test_helper"

class Collectors::Calibre::SoakReportTest < ActiveSupport::TestCase
  setup do
    @source = Source.create!(
      slug: "test-news",
      name: "Test News",
      owner_name: "Test Publisher",
      source_type: "public_reporting",
      canonical_url: "https://test.example/",
      active: true
    )
    @policy = @source.source_policies.create!(
      version: 1,
      status: "approved",
      access_method: "public_rss_and_html",
      endpoint_url: "https://test.example/feed.xml",
      reviewed_by: "Test editor",
      reviewed_at: Time.current,
      content_hash: SecureRandom.hex(32)
    )
  end

  test "passes consecutive completed cycles with matching terminal receipts" do
    ending_slot = Time.zone.parse("2026-08-11T12:00:00Z")
    3.times { |offset| complete_cycle(ending_slot - offset.hours) }

    report = Collectors::Calibre::SoakReport.new(hours: 3).call(ending_slot:)

    assert report.fetch("passed")
    assert_equal 3, report.fetch("cycles_found")
    assert_empty report.fetch("issues")
  end

  test "reports missing cycles and nonterminal source receipts" do
    ending_slot = Time.zone.parse("2026-08-11T12:00:00Z")
    cycle, = NewsCollectionCycle.begin!(
      slot_at: ending_slot,
      source_slugs: [ @source.slug ]
    )
    cycle.mark_running!
    NewsCollectionSlot.claim(source: @source, slot_at: ending_slot, cycle:)

    report = Collectors::Calibre::SoakReport.new(hours: 2).call(ending_slot:)

    assert_not report.fetch("passed")
    assert_equal %w[missing_cycle cycle_not_completed source_slot_not_terminal],
      report.fetch("issues").pluck("code")
  end

  private

  def complete_cycle(slot_at)
    claimed_at = slot_at + 5.minutes
    cycle, = NewsCollectionCycle.begin!(slot_at:, source_slugs: [ @source.slug ], now: claimed_at)
    cycle.mark_running!
    slot = NewsCollectionSlot.claim(source: @source, slot_at:, cycle:, now: claimed_at)
    run = @source.collection_runs.create!(
      source_policy: @policy,
      adapter_name: "calibre",
      adapter_version: "1",
      started_at: claimed_at,
      status: "succeeded",
      finished_at: claimed_at + 1.minute
    )
    slot.succeed!(collection_run: run, now: run.finished_at)
  end
end
