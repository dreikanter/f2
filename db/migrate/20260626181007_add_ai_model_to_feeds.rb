class AddAiModelToFeeds < ActiveRecord::Migration[8.2]
  def change
    add_column :feeds, :ai_model, :string
  end
end
