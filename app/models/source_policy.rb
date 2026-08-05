class SourcePolicy < ApplicationRecord
  enum :status, {
    draft: "draft",
    approved: "approved",
    retired: "retired"
  }, prefix: true, validate: true

  belongs_to :source
  has_many :collection_runs, dependent: :restrict_with_error
  has_many :document_snapshots, dependent: :restrict_with_error

  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validates :access_method, :endpoint_url, :content_hash, presence: true
  validates :requests_per_minute,
    numericality: { only_integer: true, greater_than: 0 }
  validates :max_concurrency,
    numericality: { only_integer: true, greater_than: 0 }
  validates :retention_days,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :version, uniqueness: { scope: :source_id }
  validate :approved_policy_has_review

  before_update :reject_changes_to_approved_policy
  before_destroy :reject_destroy

  scope :approved, -> { where(status: "approved") }

  private

  def approved_policy_has_review
    return unless status_approved?

    errors.add(:reviewed_by, "is required for an approved policy") if reviewed_by.blank?
    errors.add(:reviewed_at, "is required for an approved policy") if reviewed_at.blank?
  end

  def reject_changes_to_approved_policy
    return unless status_in_database == "approved"

    errors.add(:base, "approved source policies are immutable; create a new version")
    throw :abort
  end

  def reject_destroy
    errors.add(:base, "source policies are retained for collection history")
    throw :abort
  end
end
