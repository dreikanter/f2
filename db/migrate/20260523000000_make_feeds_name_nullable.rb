class MakeFeedsNameNullable < ActiveRecord::Migration[8.1]
  def up
    change_column_null :feeds, :name, true
  end

  def down
    change_column_null :feeds, :name, false
  end
end
