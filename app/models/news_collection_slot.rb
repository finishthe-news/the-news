class NewsCollectionSlot < ApplicationRecord
  class InvalidTransition < StandardError; end

  enum :status, {
    claimed: "claimed",
    succeeded: "succeeded",
    failed: "failed"
  }, prefix: true, validate: true

  belongs_to :source
  belongs_to :collection_run, optional: true

  validates :slot_at, :claimed_at, :lease_expires_at, presence: true
  validates :slot_at, uniqueness: { scope: :source_id }
  validates :attempts, numericality: { only_integer: true, greater_than: 0 }
  validate :slot_starts_on_the_hour
  validate :collection_run_matches_source
  validate :timestamps_match_status

  class << self
    def claim(source:, slot_at:, now: Time.current, lease_duration: 1.hour)
      source.with_lock do
        slot = find_by(source:, slot_at:)
        return if slot&.status_succeeded?
        return if slot&.status_claimed? && slot.lease_expires_at > now
        return if active_for_source(source:, now:).where.not(id: slot&.id).exists?

        slot ||= new(source:, slot_at:, attempts: 0)
        slot.assign_attributes(
          status: "claimed",
          attempts: slot.attempts + 1,
          claimed_at: now,
          lease_expires_at: now + lease_duration,
          finished_at: nil,
          collection_run: nil
        )
        slot.save!
        slot
      end
    end

    private

    def active_for_source(source:, now:)
      where(source:, status: "claimed").where("lease_expires_at > ?", now)
    end
  end

  def succeed!(collection_run:, now: Time.current)
    finish!(status: "succeeded", collection_run:, now:)
  end

  def fail!(collection_run: nil, now: Time.current)
    finish!(status: "failed", collection_run:, now:)
  end

  private

  def slot_starts_on_the_hour
    return if slot_at.blank?
    return if slot_at.min.zero? && slot_at.sec.zero?

    errors.add(:slot_at, "must start on the hour")
  end

  def collection_run_matches_source
    return unless source && collection_run
    return if collection_run.source_id == source_id

    errors.add(:collection_run, "must belong to the same source")
  end

  def timestamps_match_status
    if status_claimed?
      errors.add(:lease_expires_at, "must be after claimed_at") if
        claimed_at && lease_expires_at && lease_expires_at <= claimed_at
      errors.add(:finished_at, "must be blank while claimed") if finished_at
    else
      errors.add(:finished_at, "is required after a claim finishes") if finished_at.blank?
    end
    if status_succeeded? && collection_run.blank?
      errors.add(:collection_run, "is required for a successful claim")
    end
  end

  def finish!(status:, collection_run:, now:)
    raise InvalidTransition, "only a claimed slot can finish" unless status_claimed?

    update!(status:, collection_run:, finished_at: now)
  end
end
