class ChangePasswordUpdatedAtNullConstraint < ActiveRecord::Migration[8.1]
  def change
    change_column_null :users, :password_updated_at, false
  end
end
