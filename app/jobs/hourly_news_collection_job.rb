class HourlyNewsCollectionJob < ApplicationJob
  queue_as :collection

  limits_concurrency to: 1, key: -> { "hourly-news-collection" }, duration: 30.minutes

  def perform(slot_at: Time.current)
    normalized_slot = slot_at.in_time_zone.beginning_of_hour.iso8601
    Collectors::Calibre::SourceRegistry.new.all.each do |manifest|
      source = Source.find_by(slug: manifest.slug, active: true)
      next unless source&.approved_policy

      NewsSourceCollectionJob.perform_later(manifest.slug, slot_at: normalized_slot)
    end
  end
end
