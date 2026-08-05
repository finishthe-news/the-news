class EventClusterDocument < ApplicationRecord
  enum :role, {
    evidence: "evidence",
    discovery: "discovery",
    background: "background"
  }, prefix: true, validate: true

  belongs_to :event_cluster
  belongs_to :source_document

  validates :source_document_id, uniqueness: { scope: :event_cluster_id }
end
