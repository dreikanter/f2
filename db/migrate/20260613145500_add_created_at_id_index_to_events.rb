class AddCreatedAtIdIndexToEvents < ActiveRecord::Migration[8.2]
  def change
    # Serves the log's chronological cursor pagination: the page query
    # (ORDER BY created_at DESC, id DESC LIMIT n), the older/newer boundary
    # checks, and the page-offset count all compare the (created_at, id) tuple.
    add_index :events, [:created_at, :id]
  end
end
