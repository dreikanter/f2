class RemoveLlmUsages < ActiveRecord::Migration[8.2]
  def change
    up_only do
      execute "DELETE FROM event_references WHERE reference_type = 'LlmUsage'"
    end

    drop_table :llm_usages, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.uuid "user_id", null: false
      t.uuid "feed_id"
      t.uuid "ai_credential_id"
      t.string "profile_key"
      t.integer "stage"
      t.string "provider", null: false
      t.string "model", null: false
      t.integer "purpose", default: 0, null: false
      t.integer "input_tokens", default: 0, null: false
      t.integer "output_tokens", default: 0, null: false
      t.integer "cache_read_tokens", default: 0, null: false
      t.integer "cache_write_tokens", default: 0, null: false
      t.decimal "cost_estimate_cents", precision: 20, scale: 10
      t.integer "outcome", null: false
      t.datetime "started_at", null: false
      t.datetime "finished_at", null: false
      t.datetime "created_at", null: false
      t.datetime "updated_at", null: false
      t.integer "duration_ms"
      t.text "error_message"
      t.jsonb "retrieval", default: {}, null: false
      t.index ["ai_credential_id"], name: "index_llm_usages_on_ai_credential_id"
      t.index ["feed_id", "started_at"], name: "index_llm_usages_on_feed_id_and_started_at"
      t.index ["profile_key", "started_at"], name: "index_llm_usages_on_profile_key_and_started_at"
      t.index ["purpose", "started_at"], name: "index_llm_usages_on_purpose_and_started_at"
      t.index ["user_id", "started_at"], name: "index_llm_usages_on_user_id_and_started_at"
      t.foreign_key :ai_credentials, on_delete: :nullify
      t.foreign_key :feeds
      t.foreign_key :users
    end
  end
end
