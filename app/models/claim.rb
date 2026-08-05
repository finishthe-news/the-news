class Claim < ApplicationRecord
  enum :claim_type, {
    fact: "fact",
    allegation: "allegation",
    estimate: "estimate",
    causal: "causal",
    context: "context",
    quotation: "quotation"
  }, prefix: true, validate: true

  enum :status, {
    confirmed: "confirmed",
    attributed: "attributed",
    disputed: "disputed",
    unknown: "unknown"
  }, prefix: true, validate: true

  enum :review_state, {
    pending: "pending",
    approved: "approved",
    rejected: "rejected"
  }, prefix: true, validate: true

  enum :origin, {
    extracted: "extracted",
    human: "human",
    imported: "imported"
  }, prefix: true, validate: true

  belongs_to :event_cluster
  has_many :evidence_items, dependent: :restrict_with_error
  has_many :story_claims, dependent: :restrict_with_error
  has_many :story_versions, through: :story_claims

  validates :statement, :content_hash, presence: true
  validates :content_hash, uniqueness: { scope: :event_cluster_id }
  validates :importance, numericality: { only_integer: true }
  validate :attributed_claim_names_source

  private

  def attributed_claim_names_source
    return unless status_attributed? && attributed_to.blank?

    errors.add(:attributed_to, "is required for an attributed claim")
  end
end
