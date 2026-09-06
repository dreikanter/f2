class PreserveFractionalLlmCosts < ActiveRecord::Migration[8.2]
  def up
    change_column :llm_usages, :cost_estimate_cents, :decimal, precision: 20, scale: 10
  end

  def down
    change_column :llm_usages, :cost_estimate_cents, :integer, using: "ROUND(cost_estimate_cents)::integer"
  end
end
