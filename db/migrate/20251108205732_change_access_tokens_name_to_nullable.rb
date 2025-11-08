class ChangeAccessTokensNameToNullable < ActiveRecord::Migration[8.2]
  def change
    change_column_null :access_tokens, :name, true
  end
end
