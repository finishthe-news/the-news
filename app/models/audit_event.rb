class AuditEvent < ApplicationRecord
  include AppendOnlyRecord

  belongs_to :subject, polymorphic: true, optional: true

  validates :event_type, :actor, :event_hash, presence: true
  validates :event_hash, uniqueness: true
end
