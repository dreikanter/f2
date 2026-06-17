class CreateLlmUsages < ActiveRecord::Migration[8.1]
  def change
    create_table :llm_usages do |t|
      t.references :user, null: false, foreign_key: true
      t.references :feed, null: true, foreign_key: true
      t.references :ai_credential, null: true, foreign_key: true
      t.string :profile_key
      t.integer :stage, null: false
      t.string :provider, null: false
      t.string :model, null: false
      t.integer :purpose, null: false, default: 0
      t.integer :input_tokens, null: false, default: 0
      t.integer :output_tokens, null: false, default: 0
      t.integer :cache_read_tokens, null: false, default: 0
      t.integer :cache_write_tokens, null: false, default: 0
      t.integer :cost_estimate_cents, null: false, default: 0
      t.integer :outcome, null: false
      t.datetime :started_at, null: false
      t.datetime :finished_at, null: false

      t.timestamps
    end

    add_index :llm_usages, [:user_id, :started_at]
    add_index :llm_usages, [:feed_id, :started_at]
    add_index :llm_usages, [:profile_key, :started_at]
    add_index :llm_usages, [:purpose, :started_at]
  end
end
