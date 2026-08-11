class HourlyNewsCollectionJob < ApplicationJob
  queue_as :collection

  limits_concurrency to: 1, key: -> { "hourly-news-collection" }, duration: 30.minutes

  def perform(slot_at: Time.current)
    normalized_slot = slot_at.in_time_zone.beginning_of_hour
    manifests = Collectors::Calibre::SourceRegistry.new.all.filter do |manifest|
      source = Source.find_by(slug: manifest.slug, active: true)
      source&.approved_policy
    end
    cycle, created = NewsCollectionCycle.begin!(
      slot_at: normalized_slot,
      source_slugs: manifests.map(&:slug)
    )
    return cycle unless created

    manifests.each do |manifest|
      NewsSourceCollectionJob.perform_later(
        manifest.slug,
        slot_at: normalized_slot.iso8601,
        cycle_id: cycle.id
      )
    end
    cycle.mark_running! if manifests.any?
    cycle
  end
end
