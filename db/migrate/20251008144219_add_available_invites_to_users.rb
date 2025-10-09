class AddAvailableInvitesToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :available_invites, :integer, null: false, default: 0
  end
end
