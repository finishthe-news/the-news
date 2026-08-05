class Story < ApplicationRecord
  enum :status, {
    draft: "draft",
    review: "review",
    approved: "approved",
    published: "published",
    withdrawn: "withdrawn"
  }, prefix: true, validate: true

  enum :risk_level, {
    normal: "normal",
    elevated: "elevated",
    high: "high"
  }, prefix: true, validate: true

  has_many :story_event_clusters, dependent: :restrict_with_error
  has_many :event_clusters, through: :story_event_clusters
  has_many :story_versions, dependent: :restrict_with_error
  has_many :corrections, dependent: :restrict_with_error

  validates :slug, :section, presence: true
  validates :slug, uniqueness: true
end
