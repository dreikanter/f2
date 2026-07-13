class AddEventsForeignKeyToEventReferences < ActiveRecord::Migration[8.2]
  # event_references.event_id had no database foreign key, so a deleted event
  # could leave dangling rows (only app-level dependent: :delete_all guarded it).
  # Runs after the uuidv7 conversion, which prunes any pre-existing orphans, so
  # the constraint validates cleanly.
  def change
    add_foreign_key :event_references, :events, on_delete: :cascade
  end
end
