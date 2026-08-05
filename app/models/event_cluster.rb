class EventCluster < ApplicationRecord
  enum :status, {
    candidate: "candidate",
    active: "active",
    merged: "merged",
    rejected: "rejected"
  }, prefix: true, validate: true

  enum :risk_level, {
    normal: "normal",
    elevated: "elevated",
    high: "high"
  }, prefix: true, validate: true

  has_many :event_cluster_documents, dependent: :restrict_with_error
  has_many :source_documents, through: :event_cluster_documents
  has_many :claims, dependent: :restrict_with_error
  has_many :story_event_clusters, dependent: :restrict_with_error
  has_many :stories, through: :story_event_clusters

  validates :title, :first_seen_at, :last_seen_at, presence: true
end
