class AddEmailDeactivationToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :email_deactivated_at, :datetime
    add_column :users, :email_deactivation_reason, :string
    add_index :users, :email_deactivated_at
  end
end
