class EditionItem < ApplicationRecord
  belongs_to :edition
  belongs_to :story_version

  validates :section, presence: true
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :position, uniqueness: { scope: :edition_id }
  validates :story_version_id, uniqueness: { scope: :edition_id }
end
