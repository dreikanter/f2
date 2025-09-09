class AddNewStatusAndOwnerToAccessTokens < ActiveRecord::Migration[8.0]
  def change
    add_column :access_tokens, :owner, :string
  end
end
