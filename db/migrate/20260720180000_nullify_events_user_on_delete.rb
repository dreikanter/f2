# User#events declares dependent: :nullify (since the admin user page started
# listing a user's events), so the database FK should agree instead of
# blocking user deletion at the SQL level.
class NullifyEventsUserOnDelete < ActiveRecord::Migration[8.2]
  def change
    remove_foreign_key :events, :users
    add_foreign_key :events, :users, on_delete: :nullify
  end
end
