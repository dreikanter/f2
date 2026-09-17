class DiscardStoredLlmUsages < ActiveRecord::Migration[8.2]
  def change
    # Old accounting is intentionally discarded; rollback cannot restore it.
    up_only do
      execute "DELETE FROM event_references WHERE reference_type = 'LlmUsage'"
      execute "DELETE FROM llm_usages"
    end
  end
end
