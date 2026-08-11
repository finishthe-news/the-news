# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_11_083000) do
  create_table "artifacts", force: :cascade do |t|
    t.integer "byte_size"
    t.string "content_hash"
    t.datetime "created_at", null: false
    t.integer "edition_id", null: false
    t.text "error_message"
    t.string "format", null: false
    t.datetime "generated_at"
    t.json "metadata", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.string "storage_key"
    t.datetime "updated_at", null: false
    t.index ["edition_id", "format"], name: "index_artifacts_on_edition_id_and_format", unique: true
    t.index ["edition_id"], name: "index_artifacts_on_edition_id"
  end

  create_table "audit_events", force: :cascade do |t|
    t.string "actor", null: false
    t.datetime "created_at", null: false
    t.string "event_hash", null: false
    t.string "event_type", null: false
    t.json "payload", default: {}, null: false
    t.string "previous_hash"
    t.integer "subject_id"
    t.string "subject_type"
    t.index ["created_at"], name: "index_audit_events_on_created_at"
    t.index ["event_hash"], name: "index_audit_events_on_event_hash", unique: true
    t.index ["subject_type", "subject_id"], name: "index_audit_events_on_subject_type_and_subject_id"
  end

  create_table "claims", force: :cascade do |t|
    t.string "attributed_to"
    t.string "claim_type", default: "fact", null: false
    t.string "content_hash", null: false
    t.datetime "created_at", null: false
    t.integer "event_cluster_id", null: false
    t.integer "importance", default: 0, null: false
    t.json "metadata", default: {}, null: false
    t.datetime "occurred_at"
    t.string "origin", default: "extracted", null: false
    t.boolean "requires_human_review", default: false, null: false
    t.string "review_state", default: "pending", null: false
    t.text "statement", null: false
    t.string "status", default: "unknown", null: false
    t.datetime "updated_at", null: false
    t.index ["event_cluster_id", "content_hash"], name: "index_claims_on_event_cluster_id_and_content_hash", unique: true
    t.index ["event_cluster_id"], name: "index_claims_on_event_cluster_id"
    t.index ["review_state", "requires_human_review"], name: "index_claims_on_review_state_and_requires_human_review"
  end

  create_table "collection_runs", force: :cascade do |t|
    t.string "adapter_name", null: false
    t.string "adapter_version", null: false
    t.datetime "created_at", null: false
    t.integer "documents_created", default: 0, null: false
    t.integer "documents_seen", default: 0, null: false
    t.string "error_class"
    t.text "error_message"
    t.datetime "finished_at"
    t.json "metadata", default: {}, null: false
    t.integer "snapshots_created", default: 0, null: false
    t.integer "source_id", null: false
    t.integer "source_policy_id", null: false
    t.datetime "started_at", null: false
    t.string "status", default: "running", null: false
    t.datetime "updated_at", null: false
    t.index ["source_id", "started_at"], name: "index_collection_runs_on_source_id_and_started_at"
    t.index ["source_id"], name: "index_collection_runs_on_source_id"
    t.index ["source_policy_id"], name: "index_collection_runs_on_source_policy_id"
  end

  create_table "corrections", force: :cascade do |t|
    t.datetime "approved_at"
    t.string "approved_by"
    t.integer "corrected_story_version_id"
    t.datetime "created_at", null: false
    t.integer "edition_id", null: false
    t.datetime "published_at"
    t.text "reason", null: false
    t.string "status", default: "draft", null: false
    t.integer "story_id"
    t.string "summary", null: false
    t.integer "superseded_story_version_id"
    t.datetime "updated_at", null: false
    t.index ["corrected_story_version_id"], name: "index_corrections_on_corrected_story_version_id"
    t.index ["edition_id", "status"], name: "index_corrections_on_edition_id_and_status"
    t.index ["edition_id"], name: "index_corrections_on_edition_id"
    t.index ["story_id"], name: "index_corrections_on_story_id"
    t.index ["superseded_story_version_id"], name: "index_corrections_on_superseded_story_version_id"
  end

  create_table "deliveries", force: :cascade do |t|
    t.integer "artifact_id"
    t.datetime "attempted_at"
    t.string "channel", null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.string "destination_hash", null: false
    t.integer "edition_id", null: false
    t.text "error_message"
    t.json "metadata", default: {}, null: false
    t.string "provider_reference"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["artifact_id"], name: "index_deliveries_on_artifact_id"
    t.index ["edition_id", "channel", "destination_hash"], name: "index_deliveries_on_edition_channel_destination", unique: true
    t.index ["edition_id"], name: "index_deliveries_on_edition_id"
  end

  create_table "discovery_observations", force: :cascade do |t|
    t.string "canonical_url"
    t.integer "collection_run_id", null: false
    t.datetime "created_at", null: false
    t.string "discovered_url"
    t.json "metadata", default: {}, null: false
    t.datetime "observed_at", null: false
    t.integer "position", null: false
    t.datetime "published_at"
    t.integer "source_document_id"
    t.integer "source_id", null: false
    t.datetime "source_updated_at"
    t.datetime "updated_at", null: false
    t.index ["collection_run_id", "position"], name: "index_discovery_observations_on_run_and_position", unique: true
    t.index ["collection_run_id"], name: "index_discovery_observations_on_collection_run_id"
    t.index ["source_document_id"], name: "index_discovery_observations_on_source_document_id"
    t.index ["source_id", "canonical_url"], name: "index_discovery_observations_on_source_id_and_canonical_url"
    t.index ["source_id"], name: "index_discovery_observations_on_source_id"
  end

  create_table "document_snapshots", force: :cascade do |t|
    t.string "adapter_version", null: false
    t.integer "byte_size", null: false
    t.integer "collection_run_id"
    t.string "collector_identity", null: false
    t.datetime "completed_at", null: false
    t.string "content_hash", null: false
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "etag"
    t.string "final_url", null: false
    t.integer "http_status", null: false
    t.string "last_modified"
    t.json "payload"
    t.json "request_headers", default: {}, null: false
    t.string "requested_url", null: false
    t.json "response_headers", default: {}, null: false
    t.datetime "retrieved_at", null: false
    t.integer "source_document_id", null: false
    t.integer "source_policy_id", null: false
    t.string "storage_key"
    t.datetime "updated_at", null: false
    t.index ["collection_run_id"], name: "index_document_snapshots_on_collection_run_id"
    t.index ["retrieved_at"], name: "index_document_snapshots_on_retrieved_at"
    t.index ["source_document_id", "content_hash"], name: "index_document_snapshots_on_document_and_hash", unique: true
    t.index ["source_document_id"], name: "index_document_snapshots_on_source_document_id"
    t.index ["source_policy_id"], name: "index_document_snapshots_on_source_policy_id"
  end

  create_table "edition_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "edition_id", null: false
    t.boolean "featured", default: false, null: false
    t.integer "position", null: false
    t.boolean "required", default: false, null: false
    t.string "section", null: false
    t.integer "story_version_id", null: false
    t.datetime "updated_at", null: false
    t.index ["edition_id", "position"], name: "index_edition_items_on_edition_id_and_position", unique: true
    t.index ["edition_id", "story_version_id"], name: "index_edition_items_on_edition_id_and_story_version_id", unique: true
    t.index ["edition_id"], name: "index_edition_items_on_edition_id"
    t.index ["story_version_id"], name: "index_edition_items_on_story_version_id"
  end

  create_table "editions", force: :cascade do |t|
    t.string "access_tier", null: false
    t.datetime "approved_at"
    t.string "approved_by"
    t.string "content_hash"
    t.datetime "created_at", null: false
    t.date "edition_date", null: false
    t.string "edition_type", null: false
    t.json "metadata", default: {}, null: false
    t.datetime "published_at"
    t.string "status", default: "draft", null: false
    t.integer "target_reading_seconds", null: false
    t.string "title", null: false
    t.integer "total_word_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["edition_date", "edition_type", "access_tier", "version"], name: "index_editions_on_identity", unique: true
    t.index ["status", "edition_date"], name: "index_editions_on_status_and_edition_date"
  end

  create_table "editorial_decisions", force: :cascade do |t|
    t.string "actor", null: false
    t.datetime "created_at", null: false
    t.string "decision", null: false
    t.json "metadata", default: {}, null: false
    t.text "rationale"
    t.integer "subject_id", null: false
    t.string "subject_type", null: false
    t.datetime "updated_at", null: false
    t.index ["subject_type", "subject_id"], name: "index_editorial_decisions_on_subject_type_and_subject_id"
  end

  create_table "event_cluster_documents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "event_cluster_id", null: false
    t.string "role", default: "evidence", null: false
    t.integer "source_document_id", null: false
    t.datetime "updated_at", null: false
    t.index ["event_cluster_id", "source_document_id"], name: "index_cluster_documents_on_cluster_and_document", unique: true
    t.index ["event_cluster_id"], name: "index_event_cluster_documents_on_event_cluster_id"
    t.index ["source_document_id"], name: "index_event_cluster_documents_on_source_document_id"
  end

  create_table "event_clusters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "first_seen_at", null: false
    t.datetime "last_seen_at", null: false
    t.json "metadata", default: {}, null: false
    t.datetime "occurred_at"
    t.string "risk_level", default: "normal", null: false
    t.string "status", default: "candidate", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["status", "last_seen_at"], name: "index_event_clusters_on_status_and_last_seen_at"
  end

  create_table "evidence_items", force: :cascade do |t|
    t.integer "claim_id", null: false
    t.decimal "confidence", precision: 4, scale: 3
    t.string "content_hash", null: false
    t.datetime "created_at", null: false
    t.integer "document_snapshot_id", null: false
    t.text "excerpt", null: false
    t.string "locator"
    t.boolean "quotation", default: false, null: false
    t.text "reviewer_note"
    t.string "source_url", null: false
    t.string "support_type", default: "supports", null: false
    t.datetime "updated_at", null: false
    t.string "verification_status", default: "pending", null: false
    t.index ["claim_id", "document_snapshot_id", "content_hash"], name: "index_evidence_on_claim_snapshot_and_hash", unique: true
    t.index ["claim_id"], name: "index_evidence_items_on_claim_id"
    t.index ["document_snapshot_id"], name: "index_evidence_items_on_document_snapshot_id"
  end

  create_table "news_collection_cycles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "dispatched_at", null: false
    t.json "expected_source_slugs", default: [], null: false
    t.datetime "finished_at"
    t.datetime "slot_at", null: false
    t.string "status", default: "dispatching", null: false
    t.datetime "updated_at", null: false
    t.index ["slot_at"], name: "index_news_collection_cycles_on_slot_at", unique: true
  end

  create_table "news_collection_slots", force: :cascade do |t|
    t.integer "attempts", default: 1, null: false
    t.datetime "claimed_at", null: false
    t.integer "collection_run_id"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.datetime "lease_expires_at", null: false
    t.integer "news_collection_cycle_id"
    t.datetime "slot_at", null: false
    t.integer "source_id", null: false
    t.string "status", default: "claimed", null: false
    t.datetime "updated_at", null: false
    t.index ["collection_run_id"], name: "index_news_collection_slots_on_collection_run_id"
    t.index ["news_collection_cycle_id"], name: "index_news_collection_slots_on_news_collection_cycle_id"
    t.index ["source_id", "slot_at"], name: "index_news_collection_slots_on_source_id_and_slot_at", unique: true
    t.index ["source_id", "status", "lease_expires_at"], name: "idx_news_collection_slots_active_lease"
    t.index ["source_id"], name: "index_news_collection_slots_on_source_id"
  end

  create_table "source_documents", force: :cascade do |t|
    t.string "canonical_url", null: false
    t.datetime "created_at", null: false
    t.datetime "discovery_updated_at"
    t.string "document_type"
    t.string "external_id", null: false
    t.string "language", default: "en", null: false
    t.json "metadata", default: {}, null: false
    t.datetime "published_at"
    t.integer "source_id", null: false
    t.datetime "source_updated_at"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["published_at"], name: "index_source_documents_on_published_at"
    t.index ["source_id", "canonical_url"], name: "index_source_documents_on_source_id_and_canonical_url", unique: true
    t.index ["source_id", "external_id"], name: "index_source_documents_on_source_id_and_external_id", unique: true
    t.index ["source_id"], name: "index_source_documents_on_source_id"
  end

  create_table "source_policies", force: :cascade do |t|
    t.string "access_method", null: false
    t.json "allowed_uses", default: [], null: false
    t.text "attribution_requirements"
    t.string "content_hash", null: false
    t.datetime "created_at", null: false
    t.datetime "effective_from"
    t.datetime "effective_until"
    t.string "endpoint_url", null: false
    t.string "license_name"
    t.string "license_url"
    t.integer "max_concurrency", default: 1, null: false
    t.text "notes"
    t.integer "requests_per_minute", default: 60, null: false
    t.integer "retention_days", default: 30, null: false
    t.datetime "reviewed_at"
    t.string "reviewed_by"
    t.string "robots_url"
    t.integer "source_id", null: false
    t.string "status", default: "draft", null: false
    t.string "terms_url"
    t.datetime "updated_at", null: false
    t.integer "version", null: false
    t.index ["source_id", "status"], name: "index_source_policies_on_source_id_and_status"
    t.index ["source_id", "version"], name: "index_source_policies_on_source_id_and_version", unique: true
    t.index ["source_id"], name: "index_source_policies_on_source_id"
  end

  create_table "sources", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.string "canonical_url", null: false
    t.datetime "created_at", null: false
    t.json "metadata", default: {}, null: false
    t.string "name", null: false
    t.string "owner_name", null: false
    t.string "slug", null: false
    t.string "source_type", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_sources_on_slug", unique: true
  end

  create_table "stories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.json "metadata", default: {}, null: false
    t.boolean "requires_human_review", default: false, null: false
    t.string "risk_level", default: "normal", null: false
    t.string "section", null: false
    t.string "slug", null: false
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_stories_on_slug", unique: true
    t.index ["status", "section"], name: "index_stories_on_status_and_section"
  end

  create_table "story_claims", force: :cascade do |t|
    t.integer "claim_id", null: false
    t.datetime "created_at", null: false
    t.integer "position", null: false
    t.integer "story_version_id", null: false
    t.datetime "updated_at", null: false
    t.string "usage", default: "asserted", null: false
    t.index ["claim_id"], name: "index_story_claims_on_claim_id"
    t.index ["story_version_id", "claim_id"], name: "index_story_claims_on_version_and_claim", unique: true
    t.index ["story_version_id", "position"], name: "index_story_claims_on_story_version_id_and_position", unique: true
    t.index ["story_version_id"], name: "index_story_claims_on_story_version_id"
  end

  create_table "story_event_clusters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "event_cluster_id", null: false
    t.integer "story_id", null: false
    t.datetime "updated_at", null: false
    t.index ["event_cluster_id"], name: "index_story_event_clusters_on_event_cluster_id"
    t.index ["story_id", "event_cluster_id"], name: "index_story_clusters_on_story_and_cluster", unique: true
    t.index ["story_id"], name: "index_story_event_clusters_on_story_id"
  end

  create_table "story_versions", force: :cascade do |t|
    t.datetime "approved_at"
    t.string "approved_by"
    t.text "body", null: false
    t.string "content_hash", null: false
    t.datetime "created_at", null: false
    t.string "dek"
    t.string "generated_by"
    t.string "headline", null: false
    t.json "metadata", default: {}, null: false
    t.string "model_name"
    t.string "prompt_version"
    t.integer "reading_seconds", default: 0, null: false
    t.decimal "source_similarity_max", precision: 5, scale: 4
    t.string "status", default: "draft", null: false
    t.integer "story_id", null: false
    t.text "uncertainty_note"
    t.datetime "updated_at", null: false
    t.integer "version", null: false
    t.text "why_it_matters"
    t.integer "word_count", default: 0, null: false
    t.index ["status", "approved_at"], name: "index_story_versions_on_status_and_approved_at"
    t.index ["story_id", "version"], name: "index_story_versions_on_story_id_and_version", unique: true
    t.index ["story_id"], name: "index_story_versions_on_story_id"
  end

  add_foreign_key "artifacts", "editions"
  add_foreign_key "claims", "event_clusters"
  add_foreign_key "collection_runs", "source_policies"
  add_foreign_key "collection_runs", "sources"
  add_foreign_key "corrections", "editions"
  add_foreign_key "corrections", "stories"
  add_foreign_key "corrections", "story_versions", column: "corrected_story_version_id"
  add_foreign_key "corrections", "story_versions", column: "superseded_story_version_id"
  add_foreign_key "deliveries", "artifacts"
  add_foreign_key "deliveries", "editions"
  add_foreign_key "discovery_observations", "collection_runs"
  add_foreign_key "discovery_observations", "source_documents"
  add_foreign_key "discovery_observations", "sources"
  add_foreign_key "document_snapshots", "collection_runs"
  add_foreign_key "document_snapshots", "source_documents"
  add_foreign_key "document_snapshots", "source_policies"
  add_foreign_key "edition_items", "editions"
  add_foreign_key "edition_items", "story_versions"
  add_foreign_key "event_cluster_documents", "event_clusters"
  add_foreign_key "event_cluster_documents", "source_documents"
  add_foreign_key "evidence_items", "claims"
  add_foreign_key "evidence_items", "document_snapshots"
  add_foreign_key "news_collection_slots", "collection_runs"
  add_foreign_key "news_collection_slots", "news_collection_cycles"
  add_foreign_key "news_collection_slots", "sources"
  add_foreign_key "source_documents", "sources"
  add_foreign_key "source_policies", "sources"
  add_foreign_key "story_claims", "claims"
  add_foreign_key "story_claims", "story_versions"
  add_foreign_key "story_event_clusters", "event_clusters"
  add_foreign_key "story_event_clusters", "stories"
  add_foreign_key "story_versions", "stories"
end
