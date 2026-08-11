class AddNewsCollectionCycles < ActiveRecord::Migration[8.1]
  def change
    create_table :news_collection_cycles do |t|
      t.datetime :slot_at, null: false
      t.string :status, null: false, default: "dispatching"
      t.json :expected_source_slugs, null: false, default: []
      t.datetime :dispatched_at, null: false
      t.datetime :finished_at

      t.timestamps
    end
    add_index :news_collection_cycles, :slot_at, unique: true

    add_reference :news_collection_slots,
      :news_collection_cycle,
      foreign_key: true
  end
end
