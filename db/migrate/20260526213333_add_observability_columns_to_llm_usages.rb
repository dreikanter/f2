class AddObservabilityColumnsToLlmUsages < ActiveRecord::Migration[8.2]
  def change
    add_column :llm_usages, :duration_ms, :integer
    add_column :llm_usages, :error_message, :text
  end
end
