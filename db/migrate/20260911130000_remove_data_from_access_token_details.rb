class RemoveDataFromAccessTokenDetails < ActiveRecord::Migration[8.2]
  def change
    remove_column :access_token_details, :data, :jsonb, default: {}, null: false
  end
end
