class SourceDocument < ApplicationRecord
  belongs_to :source

  has_many :document_snapshots, dependent: :restrict_with_error
  has_many :event_cluster_documents, dependent: :restrict_with_error
  has_many :event_clusters, through: :event_cluster_documents

  validates :external_id, :canonical_url, :title, :language, presence: true
  validates :external_id, uniqueness: { scope: :source_id }
  validates :canonical_url, uniqueness: { scope: :source_id }
end
