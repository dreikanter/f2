require "test_helper"
require Rails.root.join("db/migrate/20261011130000_add_web_search_cost_to_llm_usages")

class LlmSearchCostMigrationTest < ActiveSupport::TestCase
  test "#migrate should clear usage test data while preserving other application records" do
    migration = AddWebSearchCostToLlmUsages.new
    migration.migrate(:down)
    RubyLLM::ActiveRecord::Usage.reset_column_information
    LlmUsage.reset_column_information
    feed = create(:feed)
    credential = create(:ai_credential, user: feed.user)
    chat = create(:llm_chat, feed: feed, user: feed.user, ai_credential: credential)
    message = chat.messages.create!(role: "assistant", content: "Retained message")
    RubyLLM::ActiveRecord::Usage.create!(attributes_for(:ruby_llm_usage).merge(chat: chat, message: message))

    migration.migrate(:up)
    RubyLLM::ActiveRecord::Usage.reset_column_information
    LlmUsage.reset_column_information

    assert_empty LlmUsage.all
    assert Feed.exists?(feed.id)
    assert AiCredential.exists?(credential.id)
    assert LlmChat.exists?(chat.id)
    assert_equal "Retained message", message.reload.content
    usage = create(:ruby_llm_usage, chat: chat, server_tool_use: { "web_search_requests" => 2 })
    assert_equal BigDecimal("0.05"), usage.reload.estimated_cost

    migration.migrate(:down)
    RubyLLM::ActiveRecord::Usage.reset_column_information
    assert_equal BigDecimal("0.03"), RubyLLM::ActiveRecord::Usage.find(usage.id).total_cost
    assert_not RubyLLM::ActiveRecord::Usage.column_names.include?("web_search_cost")
    assert Feed.exists?(feed.id)
  ensure
    migration.migrate(:up) unless RubyLLM::ActiveRecord::Usage.column_names.include?("web_search_cost")
    RubyLLM::ActiveRecord::Usage.reset_column_information
    LlmUsage.reset_column_information
  end
end
