class CreateLlmTranscripts < ActiveRecord::Migration[8.2]
  def change
    create_table :ruby_llm_models, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.string :model_id, null: false
      t.string :name, null: false
      t.string :provider, null: false
      t.string :family
      t.datetime :model_created_at
      t.integer :context_window
      t.integer :max_output_tokens
      t.date :knowledge_cutoff
      t.datetime :unlisted_at
      t.jsonb :modalities, default: {}
      t.jsonb :capabilities, default: []
      t.jsonb :pricing, default: {}
      t.jsonb :metadata, default: {}
      t.timestamps

      t.index [:provider, :model_id], unique: true
      t.index :provider
      t.index :family
      t.index :capabilities, using: :gin
      t.index :modalities, using: :gin
    end

    create_table :llm_chats, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :ruby_llm_model, type: :uuid, null: false, foreign_key: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :feed, type: :uuid, foreign_key: { on_delete: :nullify }
      t.references :ai_credential, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :requested_provider, null: false
      t.string :requested_model, null: false
      t.string :profile_key, null: false
      t.integer :purpose, null: false
      t.integer :status, null: false, default: 0
      t.datetime :started_at, null: false
      t.datetime :deadline_at, null: false
      t.datetime :finished_at
      t.string :error_category
      t.boolean :cancelled, null: false, default: false
      t.timestamps

      t.index :created_at
      t.index :deadline_at, where: "status = 0"
    end

    create_table :llm_messages, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :llm_chat, type: :uuid, null: false, foreign_key: true
      t.string :role, null: false
      t.text :content
      t.boolean :cache_until_here, null: false, default: false
      t.text :thinking_text
      t.text :thinking_signature
      t.jsonb :citations
      t.jsonb :server_tool_calls
      t.jsonb :raw_content
      t.jsonb :raw_reasoning
      t.string :finish_reason
      t.timestamps
    end

    create_table :ruby_llm_tool_calls, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :message, polymorphic: true, type: :uuid, null: false, index: false
      t.references :result, polymorphic: true, type: :uuid, index: false
      t.string :tool_call_id, null: false
      t.string :name, null: false
      t.text :thought_signature
      t.string :approval
      t.boolean :remote, default: false, null: false
      t.jsonb :arguments, default: {}
      t.timestamps

      t.index [:message_type, :message_id]
      t.index [:result_type, :result_id]
      t.index :tool_call_id, unique: true
      t.index :name
    end

    create_table :ruby_llm_usages, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :chat, polymorphic: true, type: :uuid, null: false, index: false
      t.references :message, polymorphic: true, type: :uuid, index: false
      t.string :operation, null: false
      t.string :provider, null: false
      t.string :model, null: false
      t.string :status, null: false
      t.integer :input_tokens
      t.integer :output_tokens
      t.integer :cache_read_tokens
      t.integer :cache_write_tokens
      t.integer :thinking_tokens
      t.decimal :input_cost, precision: 16, scale: 10
      t.decimal :output_cost, precision: 16, scale: 10
      t.decimal :cache_read_cost, precision: 16, scale: 10
      t.decimal :cache_write_cost, precision: 16, scale: 10
      t.decimal :thinking_cost, precision: 16, scale: 10
      t.decimal :total_cost, precision: 16, scale: 10
      t.timestamps

      t.index [:chat_type, :chat_id]
      t.index [:message_type, :message_id]
      t.index :status
      t.check_constraint "operation IN ('chat', 'embedding', 'moderation', 'image', 'speech', 'transcription', 'ocr', 'rerank')"
      t.check_constraint "status IN ('pending', 'succeeded', 'failed', 'cancelled')"
    end

    create_table :ruby_llm_batches, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.string :provider_batch_id, null: false
      t.string :provider, null: false
      t.string :status, null: false
      t.string :raw_status
      t.boolean :completed, null: false, default: false
      t.string :chat_type
      t.string :batch_protocol
      t.jsonb :chat_ids, default: []
      t.jsonb :request_counts
      t.jsonb :reported_cost
      t.timestamps

      t.index [:provider, :provider_batch_id], unique: true
      t.index :status
    end
  end
end
