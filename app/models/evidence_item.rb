class EvidenceItem < ApplicationRecord
  enum :support_type, {
    supports: "supports",
    contradicts: "contradicts",
    context: "context"
  }, prefix: true, validate: true

  enum :verification_status, {
    pending: "pending",
    verified: "verified",
    rejected: "rejected"
  }, prefix: true, validate: true

  belongs_to :claim
  belongs_to :document_snapshot

  validates :excerpt, :source_url, :content_hash, presence: true
  validates :content_hash,
    uniqueness: { scope: [ :claim_id, :document_snapshot_id ] }
  validates :confidence,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
    allow_nil: true
end
