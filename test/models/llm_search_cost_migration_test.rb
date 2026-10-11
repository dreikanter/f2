require "test_helper"
require Rails.root.join("db/migrate/20261011130000_add_web_search_cost_to_llm_usages")

class LlmSearchCostMigrationTest < ActiveSupport::TestCase
  test "#migrate should price retained searches and roll back without changing SDK costs or unrelated rows" do
    migration = AddWebSearchCostToLlmUsages.new
    migration.migrate(:down)
    RubyLLM::ActiveRecord::Usage.reset_column_information
    LlmUsage.reset_column_information
    chat = create(:llm_chat)
    feed = create(:feed)
    attributes = attributes_for(:ruby_llm_usage).merge(chat: chat, total_cost: BigDecimal("0.004"), server_tool_use: { "web_search_requests" => 2 })
    usage = RubyLLM::ActiveRecord::Usage.create!(attributes)
    mini = RubyLLM::ActiveRecord::Usage.create!(attributes.merge(model: "gpt-4.1-mini"))
    inclusive = RubyLLM::ActiveRecord::Usage.create!(attributes.merge(provider: "openrouter"))

    migration.migrate(:up)
    RubyLLM::ActiveRecord::Usage.reset_column_information
    LlmUsage.reset_column_information

    assert_equal BigDecimal("0.02"), LlmUsage.find(usage.id).web_search_cost
    assert_equal BigDecimal("0.024"), LlmUsage.find(usage.id).estimated_cost
    assert_nil LlmUsage.find(mini.id).estimated_cost
    assert_equal BigDecimal("0.004"), LlmUsage.find(inclusive.id).estimated_cost
    assert Feed.exists?(feed.id)

    migration.migrate(:down)
    RubyLLM::ActiveRecord::Usage.reset_column_information
    assert_equal BigDecimal("0.004"), usage.reload.total_cost
    assert_not RubyLLM::ActiveRecord::Usage.column_names.include?("web_search_cost")
    assert Feed.exists?(feed.id)
  ensure
    migration.migrate(:up) unless RubyLLM::ActiveRecord::Usage.column_names.include?("web_search_cost")
    RubyLLM::ActiveRecord::Usage.reset_column_information
    LlmUsage.reset_column_information
  end
end
