class AddSearchCredentialToFeeds < ActiveRecord::Migration[8.2]
  def change
    add_reference :feeds, :search_credential,
                  type: :uuid,
                  foreign_key: { on_delete: :nullify },
                  index: true
  end
end
