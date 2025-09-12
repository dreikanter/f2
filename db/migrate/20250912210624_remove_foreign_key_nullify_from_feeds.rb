class RemoveForeignKeyNullifyFromFeeds < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :feeds, :access_tokens
    add_foreign_key :feeds, :access_tokens
  end

  def down
    remove_foreign_key :feeds, :access_tokens
    add_foreign_key :feeds, :access_tokens, on_delete: :nullify
  end
end
