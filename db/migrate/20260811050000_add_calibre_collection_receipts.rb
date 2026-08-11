class AddCalibreCollectionReceipts < ActiveRecord::Migration[8.1]
  def change
    add_column :source_documents, :discovery_updated_at, :datetime

    create_table :discovery_observations do |t|
      t.references :source, null: false, foreign_key: true
      t.references :collection_run, null: false, foreign_key: true
      t.references :source_document, foreign_key: true
      t.integer :position, null: false
      t.string :discovered_url
      t.string :canonical_url
      t.datetime :published_at
      t.datetime :source_updated_at
      t.datetime :observed_at, null: false
      t.json :metadata, null: false, default: {}

      t.timestamps
    end
    add_index :discovery_observations,
      [ :collection_run_id, :position ],
      unique: true,
      name: "index_discovery_observations_on_run_and_position"
    add_index :discovery_observations, [ :source_id, :canonical_url ]

    create_table :news_collection_slots do |t|
      t.references :source, null: false, foreign_key: true
      t.references :collection_run, foreign_key: true
      t.datetime :slot_at, null: false
      t.string :status, null: false, default: "claimed"
      t.integer :attempts, null: false, default: 1
      t.datetime :claimed_at, null: false
      t.datetime :lease_expires_at, null: false
      t.datetime :finished_at

      t.timestamps
    end
    add_index :news_collection_slots,
      [ :source_id, :slot_at ],
      unique: true
    add_index :news_collection_slots,
      [ :source_id, :status, :lease_expires_at ],
      name: "idx_news_collection_slots_active_lease"
  end
end
