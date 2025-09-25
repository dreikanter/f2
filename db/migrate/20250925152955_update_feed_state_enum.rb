class UpdateFeedStateEnum < ActiveRecord::Migration[8.1]
  def up
    # Add inactive state and shift existing values
    # inactive: 0, disabled: 1, enabled: 2
    execute <<-SQL
      UPDATE feeds SET state = 2 WHERE state = 1; -- enabled becomes 2
      UPDATE feeds SET state = 1 WHERE state = 0; -- disabled becomes 1
    SQL
  end

  def down
    # Revert back to original enum values
    # disabled: 0, enabled: 1
    execute <<-SQL
      UPDATE feeds SET state = 0 WHERE state = 1; -- disabled becomes 0
      UPDATE feeds SET state = 1 WHERE state = 2; -- enabled becomes 1
      -- inactive feeds (0) will become disabled (0)
    SQL
  end
end
