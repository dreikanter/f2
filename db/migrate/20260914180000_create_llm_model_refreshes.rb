class CreateLlmModelRefreshes < ActiveRecord::Migration[8.2]
  def change
    create_table :llm_model_refreshes do |t|
      t.datetime :refreshed_at
      t.datetime :failed_at
      t.check_constraint "id = 1", name: "llm_model_refreshes_singleton"
    end
  end
end
