class AddAiSelectionToFeedPreviews < ActiveRecord::Migration[8.2]
  def change
    add_column :feed_previews, :ai_credential_id, :bigint
    add_column :feed_previews, :ai_model, :string
  end
end
