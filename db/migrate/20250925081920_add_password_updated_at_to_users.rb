class AddPasswordUpdatedAtToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :password_updated_at, :timestamp
  end
end
