# Marks when a token's validation run started, so a reader can tell an
# in-flight check from one whose run died without settling the record.
# See AccessTokenValidationWatchdog.
class AddValidationStartedAtToAccessTokens < ActiveRecord::Migration[8.0]
  def up
    add_column :access_tokens, :validation_started_at, :datetime

    # Tokens already sitting in pending (0) or validating (1) predate the
    # column. Their last write was the transition into that state, so it dates
    # the run closely enough for the watchdog to act on.
    execute <<~SQL
      UPDATE access_tokens
      SET validation_started_at = updated_at
      WHERE status IN (0, 1)
    SQL
  end

  def down
    remove_column :access_tokens, :validation_started_at
  end
end
