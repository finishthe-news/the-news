class StoryVersion < ApplicationRecord
  enum :status, {
    draft: "draft",
    approved: "approved",
    published: "published",
    superseded: "superseded"
  }, prefix: true, validate: true

  belongs_to :story
  has_many :story_claims, dependent: :restrict_with_error
  has_many :claims, through: :story_claims
  has_many :edition_items, dependent: :restrict_with_error

  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validates :version, uniqueness: { scope: :story_id }
  validates :headline, :body, :content_hash, presence: true
  validates :word_count, :reading_seconds,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :source_similarity_max,
    numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
    allow_nil: true
end
