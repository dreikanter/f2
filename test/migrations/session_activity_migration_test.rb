require "test_helper"
require_relative "../../db/migrate/20260902120000_add_last_seen_at_to_sessions"

class SessionActivityMigrationTest < ActiveSupport::TestCase
  test "#up should preserve all historical activity after a rollback" do
    freeze_time do
      user = create(:user)
      unseen_user = create(:user)
      old_session = create(:session, user: user, created_at: 90.days.ago, updated_at: 45.days.ago, last_seen_at: 45.days.ago)
      login = create(:session, user: user, created_at: 1.day.ago, updated_at: 1.day.ago, last_seen_at: 1.day.ago)
      migration = AddLastSeenAtToSessions.new

      migration.migrate(:down)
      assert_not Session.connection.column_exists?(:sessions, :last_seen_at)
      assert_not User.connection.column_exists?(:users, :last_seen_at)

      migration.migrate(:up)
      Session.reset_column_information
      User.reset_column_information

      assert_equal 45.days.ago, old_session.reload.last_seen_at
      assert_equal 1.day.ago, login.reload.last_seen_at
      assert_equal 1.day.ago, user.reload.last_seen_at
      assert_nil unseen_user.reload.last_seen_at
      assert_not Session.columns_hash.fetch("last_seen_at").null
    end
  end
end
