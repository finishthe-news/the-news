class DiscoveryObservation < ApplicationRecord
  include AppendOnlyRecord

  belongs_to :source
  belongs_to :collection_run
  belongs_to :source_document, optional: true

  validates :observed_at, presence: true
  validates :position,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 },
    uniqueness: { scope: :collection_run_id }
  validate :source_matches_collection_run
  validate :document_matches_source

  private

  def source_matches_collection_run
    return unless source && collection_run
    return if collection_run.source_id == source_id

    errors.add(:collection_run, "must belong to the same source")
  end

  def document_matches_source
    return unless source && source_document
    return if source_document.source_id == source_id

    errors.add(:source_document, "must belong to the same source")
  end
end
