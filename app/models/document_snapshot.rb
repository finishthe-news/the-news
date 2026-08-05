class DocumentSnapshot < ApplicationRecord
  include AppendOnlyRecord

  belongs_to :source_document
  belongs_to :source_policy
  belongs_to :collection_run, optional: true

  has_many :evidence_items, dependent: :restrict_with_error

  validates :requested_url, :final_url, :retrieved_at, :completed_at,
    :http_status, :collector_identity, :adapter_version, :content_hash,
    :byte_size, presence: true
  validates :content_hash, uniqueness: { scope: :source_document_id }
  validates :byte_size, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
