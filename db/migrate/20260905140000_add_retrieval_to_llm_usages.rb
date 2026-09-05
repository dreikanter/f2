class AddRetrievalToLlmUsages < ActiveRecord::Migration[8.2]
  def change
    add_column :llm_usages, :retrieval, :jsonb, default: {}, null: false
  end
end
