class AddLlmCredentialIdToFeeds < ActiveRecord::Migration[8.1]
  def change
    add_reference :feeds, :llm_credential, null: true, foreign_key: true
  end
end
