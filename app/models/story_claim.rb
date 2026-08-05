class StoryClaim < ApplicationRecord
  enum :usage, {
    asserted: "asserted",
    attributed: "attributed",
    context: "context"
  }, prefix: true, validate: true

  belongs_to :story_version
  belongs_to :claim

  validates :claim_id, uniqueness: { scope: :story_version_id }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :position, uniqueness: { scope: :story_version_id }
end
