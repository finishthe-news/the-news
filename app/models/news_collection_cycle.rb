class NewsCollectionCycle < ApplicationRecord
  class SourceSetMismatch < StandardError; end

  enum :status, {
    dispatching: "dispatching",
    running: "running",
    completed: "completed"
  }, prefix: true, validate: true

  has_many :news_collection_slots, dependent: :restrict_with_error

  validates :slot_at, :dispatched_at, presence: true
  validates :slot_at, uniqueness: true
  validate :slot_starts_on_the_hour
  validate :expected_sources_are_canonical
  validate :finished_at_matches_status

  class << self
    def begin!(slot_at:, source_slugs:, now: Time.current)
      normalized_slot = slot_at.in_time_zone.beginning_of_hour
      normalized_sources = source_slugs.map(&:to_s).uniq.sort

      transaction do
        cycle = lock.find_by(slot_at: normalized_slot)
        if cycle
          unless cycle.expected_source_slugs == normalized_sources
            raise SourceSetMismatch, "source set already recorded for #{normalized_slot.iso8601}"
          end
          [ cycle, false ]
        else
          cycle = create!(
            slot_at: normalized_slot,
            status: normalized_sources.empty? ? "completed" : "dispatching",
            expected_source_slugs: normalized_sources,
            dispatched_at: now,
            finished_at: normalized_sources.empty? ? now : nil
          )
          [ cycle, true ]
        end
      end
    end
  end

  def mark_running!
    update!(status: "running", finished_at: nil)
  end

  def refresh_completion!(now: Time.current)
    with_lock do
      terminal_slugs = news_collection_slots
        .where(status: %w[succeeded failed])
        .joins(:source)
        .pluck("sources.slug")
        .uniq
        .sort
      return false unless terminal_slugs == expected_source_slugs

      update!(status: "completed", finished_at: now)
      true
    end
  end

  private

  def slot_starts_on_the_hour
    return if slot_at.blank?
    return if slot_at.min.zero? && slot_at.sec.zero?

    errors.add(:slot_at, "must start on the hour")
  end

  def expected_sources_are_canonical
    values = Array(expected_source_slugs)
    return if values == values.map(&:to_s).uniq.sort

    errors.add(:expected_source_slugs, "must be sorted unique strings")
  end

  def finished_at_matches_status
    if status_completed? && finished_at.blank?
      errors.add(:finished_at, "is required when completed")
    elsif !status_completed? && finished_at.present?
      errors.add(:finished_at, "must be blank until completed")
    end
  end
end
