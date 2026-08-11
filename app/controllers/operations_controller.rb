class OperationsController < ApplicationController
  SourceStatus = Data.define(
    :source,
    :policy,
    :last_slot,
    :document_count,
    :successful_runs,
    :failed_runs
  )

  def show
    manifests = Collectors::Calibre::SourceRegistry.new.all
    sources_by_slug = Source.where(slug: manifests.map(&:slug)).index_by(&:slug)
    @source_statuses = manifests.filter_map do |manifest|
      source = sources_by_slug[manifest.slug]
      next unless source

      SourceStatus.new(
        source:,
        policy: source.source_policies.order(version: :desc).first,
        last_slot: source.news_collection_slots.order(slot_at: :desc).first,
        document_count: source.source_documents.count,
        successful_runs: source.collection_runs.status_succeeded.count,
        failed_runs: source.collection_runs.status_failed.count
      )
    end
    @cycles = NewsCollectionCycle.order(slot_at: :desc).limit(24).includes(
      news_collection_slots: :source
    )
    ending_slot = @cycles.first&.slot_at || Time.current.beginning_of_hour
    @soak_report = Collectors::Calibre::SoakReport.new.call(ending_slot:)
    @total_documents = SourceDocument.where(source: sources_by_slug.values).count
    @last_updated_at = Time.current
  end
end
