class IndexFeedIdentificationEventsByRun < ActiveRecord::Migration[8.2]
  def change
    add_index :events, "(metadata -> 'stats' ->> 'run_id')",
              unique: true, where: "type = 'feed_identification'",
              name: "index_feed_identification_events_on_run_id"
  end
end
