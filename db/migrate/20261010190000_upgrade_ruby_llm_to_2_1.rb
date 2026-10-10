class UpgradeRubyLlmTo21 < ActiveRecord::Migration[8.2]
  def change
    create_table :ruby_llm_mcp_credentials, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.references :owner, polymorphic: true, type: :uuid
      t.string :key, null: false
      t.text :data
      t.timestamps

      t.index :key, unique: true
    end

    add_column :ruby_llm_tool_calls, :mcp_state, :jsonb
    add_column :ruby_llm_tool_calls, :mcp_result, :jsonb
    add_column :ruby_llm_usages, :server_tool_use, :jsonb
    add_reference :ruby_llm_usages, :owner, polymorphic: true, type: :uuid

    # Keep relaxed constraints on rollback to preserve usage recorded by 2.1.
    reversible do |direction|
      direction.up do
        change_column_null :ruby_llm_usages, :chat_type, true
        change_column_null :ruby_llm_usages, :chat_id, true
        operations = check_constraints(:ruby_llm_usages).find { |constraint| constraint.expression.include?("operation") }
        remove_check_constraint :ruby_llm_usages, name: operations.name
        add_check_constraint :ruby_llm_usages,
          "operation IN ('chat', 'embedding', 'moderation', 'image', 'speech', 'transcription', 'ocr', 'rerank', 'judgment', 'video', 'research')",
          name: "ruby_llm_usages_operation_check"
      end
    end

    add_column :llm_messages, :cache_ttl, :string

    create_table :ruby_llm_provider_files, id: :uuid, default: -> { "uuidv7()" } do |t|
      t.string :blob_key, null: false
      t.string :provider, null: false
      t.string :account, null: false
      t.text :file_id, null: false
      t.datetime :expires_at
      t.timestamps

      t.index [:blob_key, :provider, :account], unique: true, name: "index_ruby_llm_provider_files_uniqueness"
    end
  end
end
