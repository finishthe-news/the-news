class NewsSourceCollectionJob < ApplicationJob
  queue_as :collection

  limits_concurrency to: 1,
    key: ->(source_slug, **) { "news-source:#{source_slug}" },
    duration: 2.hours

  def perform(source_slug, slot_at:)
    manifest = Collectors::Calibre::SourceRegistry.new.fetch(source_slug)
    source = Source.find_by!(slug: source_slug, active: true)
    slot_time = Time.iso8601(slot_at).in_time_zone.beginning_of_hour
    slot = NewsCollectionSlot.claim(
      source:,
      slot_at: slot_time,
      lease_duration: manifest.limits.timeout_seconds.seconds + 5.minutes
    )
    return unless slot

    run = collector_for(source:, manifest:).call
    slot.succeed!(collection_run: run)
  rescue => error
    run = error.collection_run if error.respond_to?(:collection_run)
    slot&.fail!(collection_run: run)
    raise
  end

  private

  def collector_for(source:, manifest:)
    Collectors::Calibre::Collector.new(source:, manifest:)
  end
end
