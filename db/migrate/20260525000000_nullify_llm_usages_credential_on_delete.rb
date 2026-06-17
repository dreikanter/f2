class NullifyLlmUsagesCredentialOnDelete < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :llm_usages, :ai_credentials
    add_foreign_key :llm_usages, :ai_credentials, on_delete: :nullify
  end

  def down
    remove_foreign_key :llm_usages, :ai_credentials
    add_foreign_key :llm_usages, :ai_credentials
  end
end
