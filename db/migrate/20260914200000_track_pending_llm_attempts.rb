class TrackPendingLlmAttempts < ActiveRecord::Migration[8.2]
  def change
    add_column :llm_usages, :deadline_at, :datetime
    add_column :llm_usages, :thinking_tokens, :integer
    add_index :llm_usages, :deadline_at, where: "outcome = 5"

    change_column_null :llm_usages, :finished_at, true
    change_column_null :llm_usages, :input_tokens, true
    change_column_null :llm_usages, :output_tokens, true
    change_column_null :llm_usages, :cache_read_tokens, true
    change_column_null :llm_usages, :cache_write_tokens, true
    change_column_default :llm_usages, :input_tokens, from: 0, to: nil
    change_column_default :llm_usages, :output_tokens, from: 0, to: nil
    change_column_default :llm_usages, :cache_read_tokens, from: 0, to: nil
    change_column_default :llm_usages, :cache_write_tokens, from: 0, to: nil

    reversible do |direction|
      direction.down do
        # Rollback maps unfinished attempts to legacy timeouts and unknown counts to required zero placeholders.
        execute <<~SQL
          UPDATE llm_usages
          SET outcome = CASE WHEN outcome IN (5, 6) THEN 4 ELSE outcome END,
              finished_at = COALESCE(finished_at, deadline_at, updated_at),
              input_tokens = COALESCE(input_tokens, 0),
              output_tokens = COALESCE(output_tokens, 0),
              cache_read_tokens = COALESCE(cache_read_tokens, 0),
              cache_write_tokens = COALESCE(cache_write_tokens, 0)
          WHERE outcome IN (5, 6) OR finished_at IS NULL
             OR input_tokens IS NULL OR output_tokens IS NULL
             OR cache_read_tokens IS NULL OR cache_write_tokens IS NULL
        SQL
      end
    end
  end
end
