class CollectionRun < ApplicationRecord
  enum :status, {
    running: "running",
    succeeded: "succeeded",
    failed: "failed"
  }, prefix: true, validate: true

  belongs_to :source
  belongs_to :source_policy
  has_many :document_snapshots, dependent: :restrict_with_error
  has_many :discovery_observations, dependent: :restrict_with_error
  has_one :news_collection_slot, dependent: :restrict_with_error

  validates :adapter_name, :adapter_version, :started_at, presence: true
  validates :documents_seen, :documents_created, :snapshots_created,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
