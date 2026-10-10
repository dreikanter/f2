require "test_helper"
require Rails.root.join("db/migrate/20261010190000_upgrade_ruby_llm_to_2_1")

class UpgradeRubyLlmTo21Test < ActiveSupport::TestCase
  test "#change should preserve existing chat usage through rollback and upgrade" do
    usage = create(:ruby_llm_usage)
    chat_id = usage.chat_id
    connection = ActiveRecord::Base.connection
    migration = UpgradeRubyLlmTo21.new

    ActiveRecord::Migration.suppress_messages do
      migration.migrate(:down)
      assert_not connection.column_exists?(:llm_messages, :cache_ttl)
      assert_not connection.column_exists?(:ruby_llm_tool_calls, :mcp_state)
      assert_not connection.table_exists?(:ruby_llm_mcp_credentials)
      assert_not connection.table_exists?(:ruby_llm_provider_files)
      assert_not connection.columns(:ruby_llm_usages).find { |column| column.name == "chat_id" }.null

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
  end
end
