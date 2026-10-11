class AddWebSearchCostToLlmUsages < ActiveRecord::Migration[8.2]
  def up
    add_column :ruby_llm_usages, :web_search_cost, :decimal, precision: 16, scale: 10, default: 0

    # Existing usage rows are test data without complete search pricing.
    execute "DELETE FROM ruby_llm_usages"
  end

  def down
    remove_column :ruby_llm_usages, :web_search_cost
  end
end
