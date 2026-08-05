class EditorialDecision < ApplicationRecord
  belongs_to :subject, polymorphic: true

  validates :decision, :actor, presence: true
end
