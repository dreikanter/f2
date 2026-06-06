class CreateEventReferences < ActiveRecord::Migration[8.2]
  def change
    create_table :event_references do |t|
      t.references :event, null: false, index: false
      t.references :reference, polymorphic: true, null: false

      t.timestamps
    end

    add_index :event_references,
              [:event_id, :reference_type, :reference_id],
              unique: true,
              name: "index_event_references_on_event_and_reference"
  end
end
