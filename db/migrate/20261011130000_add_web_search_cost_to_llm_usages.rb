class AddWebSearchCostToLlmUsages < ActiveRecord::Migration[8.2]
  def up
    add_column :ruby_llm_usages, :web_search_cost, :decimal, precision: 16, scale: 10, default: 0

    # Historical mini-model content prices cannot be recovered reliably.
    execute <<~SQL
      UPDATE ruby_llm_usages
      SET web_search_cost = CASE
        WHEN model ~ '^gpt-(4o|4[.]1)-mini(-[0-9]{4}-[0-9]{2}-[0-9]{2})?$' THEN NULL
        ELSE (server_tool_use->>'web_search_requests')::numeric * 0.01
      END
      WHERE provider = 'openai'
        AND (server_tool_use->>'web_search_requests')::numeric > 0
    SQL
  end

  def down
    remove_column :ruby_llm_usages, :web_search_cost
  end
end
