class StoryEventCluster < ApplicationRecord
  belongs_to :story
  belongs_to :event_cluster

  validates :event_cluster_id, uniqueness: { scope: :story_id }
end
