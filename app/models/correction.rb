class Correction < ApplicationRecord
  enum :status, {
    draft: "draft",
    approved: "approved",
    published: "published"
  }, prefix: true, validate: true

  belongs_to :edition
  belongs_to :story, optional: true
  belongs_to :superseded_story_version, class_name: "StoryVersion", optional: true
  belongs_to :corrected_story_version, class_name: "StoryVersion", optional: true

  validates :summary, :reason, presence: true
end
