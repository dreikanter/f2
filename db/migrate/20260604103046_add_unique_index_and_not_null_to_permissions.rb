class AddUniqueIndexAndNotNullToPermissions < ActiveRecord::Migration[8.2]
  def up
    change_column_null :permissions, :name, false
    add_index :permissions, [:user_id, :name], unique: true
  end

  def down
    remove_index :permissions, [:user_id, :name]
    change_column_null :permissions, :name, true
  end
end
