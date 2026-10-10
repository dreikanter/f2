require "test_helper"
require Rails.root.join("db/migrate/20261010190000_upgrade_ruby_llm_to_2_1")

class UpgradeRubyLlmTo21Test < ActiveSupport::TestCase
  test "#change should preserve old and new usage through rollback and upgrade" do
    usage = create(:ruby_llm_usage)
    chat_id = usage.chat_id
    judgment = create(:ruby_llm_usage, chat: nil, owner: create(:user), operation: "judgment")
    connection = ActiveRecord::Base.connection
    migration = UpgradeRubyLlmTo21.new

    ActiveRecord::Migration.suppress_messages do
      migration.migrate(:down)
      assert_not connection.column_exists?(:llm_messages, :cache_ttl)
      assert_not connection.column_exists?(:ruby_llm_tool_calls, :mcp_state)
      assert_not connection.table_exists?(:ruby_llm_mcp_credentials)
      assert_not connection.table_exists?(:ruby_llm_provider_files)
      assert connection.columns(:ruby_llm_usages).find { |column| column.name == "chat_id" }.null
      assert_equal chat_id, usage.reload.chat_id
      assert_equal "judgment", judgment.reload.operation
      assert_nil judgment.chat_id
      assert_equal BigDecimal("0.03"), judgment.total_cost

      migration.migrate(:up)
    end

    assert connection.column_exists?(:llm_messages, :cache_ttl)
    assert connection.column_exists?(:ruby_llm_tool_calls, :mcp_state)
    assert connection.column_exists?(:ruby_llm_tool_calls, :mcp_result)
    assert connection.column_exists?(:ruby_llm_usages, :server_tool_use)
    assert connection.column_exists?(:ruby_llm_usages, :owner_id)
    assert connection.table_exists?(:ruby_llm_mcp_credentials)
    assert connection.table_exists?(:ruby_llm_provider_files)
    assert_equal chat_id, usage.reload.chat_id
    assert_equal BigDecimal("0.03"), usage.total_cost
    assert_equal "judgment", judgment.reload.operation
    assert_nil judgment.chat_id
  end
end
