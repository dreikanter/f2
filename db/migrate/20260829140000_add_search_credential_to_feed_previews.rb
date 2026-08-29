class AddSearchCredentialToFeedPreviews < ActiveRecord::Migration[8.0]
  def up
    add_reference :feed_previews, :search_credential, type: :uuid,
                  foreign_key: { on_delete: :nullify }

    # Existing AI preview digests include a search credential id, but the rows
    # do not reveal which one. They are disposable caches, so drop them.
    execute "DELETE FROM feed_previews WHERE ai_credential_id IS NOT NULL"
  end

  def down
    remove_reference :feed_previews, :search_credential, foreign_key: true
  end
end
