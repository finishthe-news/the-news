class Artifact < ApplicationRecord
  enum :format, {
    web: "web",
    rss: "rss",
    email: "email",
    pdf: "pdf",
    epub: "epub"
  }, prefix: true, validate: true

  enum :status, {
    pending: "pending",
    generated: "generated",
    failed: "failed"
  }, prefix: true, validate: true

  belongs_to :edition
  has_many :deliveries, dependent: :restrict_with_error

  validates :format, uniqueness: { scope: :edition_id }
  validates :byte_size,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    allow_nil: true
end
