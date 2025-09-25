class RemoveInactiveStateFromFeeds < ActiveRecord::Migration[8.1]
  def up
    # Convert any inactive feeds to disabled (state: 0 -> 0, which is now disabled)
    # Since we're changing the enum mapping from:
    #   OLD: { inactive: 0, disabled: 1, enabled: 2 }
    #   NEW: { disabled: 0, enabled: 1 }
    # We need to convert:
    #   - inactive (0) -> disabled (0) - no change needed
    #   - disabled (1) -> disabled (0)
    #   - enabled (2) -> enabled (1)

    execute <<-SQL
      UPDATE feeds
      SET state = 0
      WHERE state = 1;
    SQL

    execute <<-SQL
      UPDATE feeds
      SET state = 1
      WHERE state = 2;
    SQL
  end

  def down
    # Convert back from new enum to old enum
    execute <<-SQL
      UPDATE feeds
      SET state = 2
      WHERE state = 1;
    SQL

    execute <<-SQL
      UPDATE feeds
      SET state = 1
      WHERE state = 0;
    SQL

    # Note: We can't restore the original inactive state distinction
    # All disabled feeds will become disabled (1), none will be inactive (0)
  end
end
