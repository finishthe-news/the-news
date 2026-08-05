class Delivery < ApplicationRecord
  enum :channel, {
    web: "web",
    rss: "rss",
    email: "email",
    pdf_email: "pdf_email",
    epub_email: "epub_email",
    download: "download"
  }, prefix: true, validate: true

  enum :status, {
    pending: "pending",
    attempted: "attempted",
    delivered: "delivered",
    failed: "failed"
  }, prefix: true, validate: true

  belongs_to :edition
  belongs_to :artifact, optional: true

  validates :destination_hash, presence: true
  validates :destination_hash, uniqueness: { scope: [ :edition_id, :channel ] }
end
