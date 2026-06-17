class RenameLlmCredentialsToAiCredentials < ActiveRecord::Migration[8.2]
  def change
    rename_table :llm_credentials, :ai_credentials

    rename_index :ai_credentials,
                 "index_llm_credentials_on_user_provider_default",
                 "index_ai_credentials_on_user_provider_default"

    rename_column :feeds, :llm_credential_id, :ai_credential_id
    rename_column :llm_usages, :llm_credential_id, :ai_credential_id
  end
end
