class Edition < ApplicationRecord
  enum :edition_type, {
    weekday: "weekday",
    weekend: "weekend"
  }, prefix: true, validate: true

  enum :access_tier, {
    top_ten: "top_ten",
    complete: "complete",
    weekend: "weekend"
  }, prefix: true, validate: true

  enum :status, {
    draft: "draft",
    review: "review",
    approved: "approved",
    published: "published",
    corrected: "corrected"
  }, prefix: true, validate: true

  has_many :edition_items, dependent: :restrict_with_error
  has_many :story_versions, through: :edition_items
  has_many :artifacts, dependent: :restrict_with_error
  has_many :deliveries, dependent: :restrict_with_error
  has_many :corrections, dependent: :restrict_with_error

  validates :edition_date, :title, presence: true
  validates :version, numericality: { only_integer: true, greater_than: 0 }
  validates :target_reading_seconds, :total_word_count,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :version,
    uniqueness: { scope: [ :edition_date, :edition_type, :access_tier ] }
end
