class CreateNewsroomRecords < ActiveRecord::Migration[8.1]
  def change
    create_table :sources do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :source_type, null: false
      t.string :owner_name, null: false
      t.string :canonical_url, null: false
      t.boolean :active, null: false, default: false
      t.json :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :sources, :slug, unique: true

    create_table :source_policies do |t|
      t.references :source, null: false, foreign_key: true
      t.integer :version, null: false
      t.string :status, null: false, default: "draft"
      t.string :access_method, null: false
      t.string :endpoint_url, null: false
      t.string :terms_url
      t.string :license_name
      t.string :license_url
      t.string :robots_url
      t.integer :requests_per_minute, null: false, default: 60
      t.integer :max_concurrency, null: false, default: 1
      t.integer :retention_days, null: false, default: 30
      t.json :allowed_uses, null: false, default: []
      t.text :attribution_requirements
      t.text :notes
      t.string :reviewed_by
      t.datetime :reviewed_at
      t.datetime :effective_from
      t.datetime :effective_until
      t.string :content_hash, null: false

      t.timestamps
    end
    add_index :source_policies, [ :source_id, :version ], unique: true
    add_index :source_policies, [ :source_id, :status ]

    create_table :collection_runs do |t|
      t.references :source, null: false, foreign_key: true
      t.references :source_policy, null: false, foreign_key: true
      t.string :adapter_name, null: false
      t.string :adapter_version, null: false
      t.string :status, null: false, default: "running"
      t.datetime :started_at, null: false
      t.datetime :finished_at
      t.integer :documents_seen, null: false, default: 0
      t.integer :documents_created, null: false, default: 0
      t.integer :snapshots_created, null: false, default: 0
      t.string :error_class
      t.text :error_message
      t.json :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :collection_runs, [ :source_id, :started_at ]

    create_table :source_documents do |t|
      t.references :source, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :canonical_url, null: false
      t.string :title, null: false
      t.string :document_type
      t.string :language, null: false, default: "en"
      t.datetime :published_at
      t.datetime :source_updated_at
      t.json :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :source_documents, [ :source_id, :external_id ], unique: true
    add_index :source_documents, [ :source_id, :canonical_url ], unique: true
    add_index :source_documents, :published_at

    create_table :document_snapshots do |t|
      t.references :source_document, null: false, foreign_key: true
      t.references :source_policy, null: false, foreign_key: true
      t.references :collection_run, foreign_key: true
      t.string :requested_url, null: false
      t.string :final_url, null: false
      t.datetime :retrieved_at, null: false
      t.datetime :completed_at, null: false
      t.integer :http_status, null: false
      t.string :content_type
      t.string :etag
      t.string :last_modified
      t.string :collector_identity, null: false
      t.string :adapter_version, null: false
      t.string :content_hash, null: false
      t.integer :byte_size, null: false
      t.string :storage_key
      t.json :payload
      t.json :request_headers, null: false, default: {}
      t.json :response_headers, null: false, default: {}

      t.timestamps
    end
    add_index :document_snapshots,
      [ :source_document_id, :content_hash ],
      unique: true,
      name: "index_document_snapshots_on_document_and_hash"
    add_index :document_snapshots, :retrieved_at

    create_table :event_clusters do |t|
      t.string :title, null: false
      t.string :status, null: false, default: "candidate"
      t.string :risk_level, null: false, default: "normal"
      t.datetime :occurred_at
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.json :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :event_clusters, [ :status, :last_seen_at ]

    create_table :event_cluster_documents do |t|
      t.references :event_cluster, null: false, foreign_key: true
      t.references :source_document, null: false, foreign_key: true
      t.string :role, null: false, default: "evidence"

      t.timestamps
    end
    add_index :event_cluster_documents,
      [ :event_cluster_id, :source_document_id ],
      unique: true,
      name: "index_cluster_documents_on_cluster_and_document"

    create_table :claims do |t|
      t.references :event_cluster, null: false, foreign_key: true
      t.text :statement, null: false
      t.string :claim_type, null: false, default: "fact"
      t.string :status, null: false, default: "unknown"
      t.string :review_state, null: false, default: "pending"
      t.string :origin, null: false, default: "extracted"
      t.string :attributed_to
      t.datetime :occurred_at
      t.integer :importance, null: false, default: 0
      t.boolean :requires_human_review, null: false, default: false
      t.string :content_hash, null: false
      t.json :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :claims, [ :event_cluster_id, :content_hash ], unique: true
    add_index :claims, [ :review_state, :requires_human_review ]

    create_table :evidence_items do |t|
      t.references :claim, null: false, foreign_key: true
      t.references :document_snapshot, null: false, foreign_key: true
      t.string :support_type, null: false, default: "supports"
      t.string :verification_status, null: false, default: "pending"
      t.text :excerpt, null: false
      t.string :locator
      t.string :source_url, null: false
      t.boolean :quotation, null: false, default: false
      t.decimal :confidence, precision: 4, scale: 3
      t.text :reviewer_note
      t.string :content_hash, null: false

      t.timestamps
    end
    add_index :evidence_items,
      [ :claim_id, :document_snapshot_id, :content_hash ],
      unique: true,
      name: "index_evidence_on_claim_snapshot_and_hash"

    create_table :stories do |t|
      t.string :slug, null: false
      t.string :status, null: false, default: "draft"
      t.string :section, null: false
      t.string :risk_level, null: false, default: "normal"
      t.boolean :requires_human_review, null: false, default: false
      t.json :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :stories, :slug, unique: true
    add_index :stories, [ :status, :section ]

    create_table :story_event_clusters do |t|
      t.references :story, null: false, foreign_key: true
      t.references :event_cluster, null: false, foreign_key: true

      t.timestamps
    end
    add_index :story_event_clusters,
      [ :story_id, :event_cluster_id ],
      unique: true,
      name: "index_story_clusters_on_story_and_cluster"

    create_table :story_versions do |t|
      t.references :story, null: false, foreign_key: true
      t.integer :version, null: false
      t.string :status, null: false, default: "draft"
      t.string :headline, null: false
      t.string :dek
      t.text :body, null: false
      t.text :why_it_matters
      t.text :uncertainty_note
      t.integer :word_count, null: false, default: 0
      t.integer :reading_seconds, null: false, default: 0
      t.string :generated_by
      t.string :model_name
      t.string :prompt_version
      t.string :approved_by
      t.datetime :approved_at
      t.decimal :source_similarity_max, precision: 5, scale: 4
      t.string :content_hash, null: false
      t.json :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :story_versions, [ :story_id, :version ], unique: true
    add_index :story_versions, [ :status, :approved_at ]

    create_table :story_claims do |t|
      t.references :story_version, null: false, foreign_key: true
      t.references :claim, null: false, foreign_key: true
      t.string :usage, null: false, default: "asserted"
      t.integer :position, null: false

      t.timestamps
    end
    add_index :story_claims,
      [ :story_version_id, :claim_id ],
      unique: true,
      name: "index_story_claims_on_version_and_claim"
    add_index :story_claims, [ :story_version_id, :position ], unique: true

    create_table :editions do |t|
      t.date :edition_date, null: false
      t.string :edition_type, null: false
      t.string :access_tier, null: false
      t.integer :version, null: false, default: 1
      t.string :status, null: false, default: "draft"
      t.string :title, null: false
      t.integer :target_reading_seconds, null: false
      t.integer :total_word_count, null: false, default: 0
      t.string :approved_by
      t.datetime :approved_at
      t.datetime :published_at
      t.string :content_hash
      t.json :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :editions,
      [ :edition_date, :edition_type, :access_tier, :version ],
      unique: true,
      name: "index_editions_on_identity"
    add_index :editions, [ :status, :edition_date ]

    create_table :edition_items do |t|
      t.references :edition, null: false, foreign_key: true
      t.references :story_version, null: false, foreign_key: true
      t.string :section, null: false
      t.integer :position, null: false
      t.boolean :featured, null: false, default: false
      t.boolean :required, null: false, default: false

      t.timestamps
    end
    add_index :edition_items, [ :edition_id, :position ], unique: true
    add_index :edition_items, [ :edition_id, :story_version_id ], unique: true

    create_table :artifacts do |t|
      t.references :edition, null: false, foreign_key: true
      t.string :format, null: false
      t.string :status, null: false, default: "pending"
      t.string :storage_key
      t.string :content_hash
      t.integer :byte_size
      t.datetime :generated_at
      t.text :error_message
      t.json :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :artifacts, [ :edition_id, :format ], unique: true

    create_table :deliveries do |t|
      t.references :edition, null: false, foreign_key: true
      t.references :artifact, foreign_key: true
      t.string :channel, null: false
      t.string :status, null: false, default: "pending"
      t.string :destination_hash, null: false
      t.string :provider_reference
      t.datetime :attempted_at
      t.datetime :delivered_at
      t.text :error_message
      t.json :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :deliveries,
      [ :edition_id, :channel, :destination_hash ],
      unique: true,
      name: "index_deliveries_on_edition_channel_destination"

    create_table :corrections do |t|
      t.references :edition, null: false, foreign_key: true
      t.references :story, foreign_key: true
      t.references :superseded_story_version,
        foreign_key: { to_table: :story_versions }
      t.references :corrected_story_version,
        foreign_key: { to_table: :story_versions }
      t.string :status, null: false, default: "draft"
      t.string :summary, null: false
      t.text :reason, null: false
      t.string :approved_by
      t.datetime :approved_at
      t.datetime :published_at

      t.timestamps
    end
    add_index :corrections, [ :edition_id, :status ]

    create_table :editorial_decisions do |t|
      t.string :subject_type, null: false
      t.integer :subject_id, null: false
      t.string :decision, null: false
      t.string :actor, null: false
      t.text :rationale
      t.json :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :editorial_decisions, [ :subject_type, :subject_id ]

    create_table :audit_events do |t|
      t.string :event_type, null: false
      t.string :actor, null: false
      t.string :subject_type
      t.integer :subject_id
      t.json :payload, null: false, default: {}
      t.string :previous_hash
      t.string :event_hash, null: false

      t.datetime :created_at, null: false
    end
    add_index :audit_events, :event_hash, unique: true
    add_index :audit_events, [ :subject_type, :subject_id ]
    add_index :audit_events, :created_at
  end
end
