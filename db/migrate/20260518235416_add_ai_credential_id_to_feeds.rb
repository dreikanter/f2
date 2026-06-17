class AddAiCredentialIdToFeeds < ActiveRecord::Migration[8.1]
  def change
    add_reference :feeds,
                  :ai_credential,
                  null: true,
                  foreign_key: { on_delete: :nullify }
  end
end
