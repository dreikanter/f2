require "test_helper"

class LlmUsageTest < ActiveSupport::TestCase
  test "#estimated_cost should include persisted search charges without changing SDK token costs" do
    usage = create(:ruby_llm_usage, total_cost: "0.004", server_tool_use: { "web_search_requests" => 2 })

    assert_nil usage.message
    assert_equal BigDecimal("0.02"), usage.reload.web_search_cost
    assert_equal BigDecimal("0.004"), usage.total_cost
    assert_equal BigDecimal("0.024"), usage.estimated_cost

    usage.update!(server_tool_use: { "web_search_requests" => 99 })
    assert_equal BigDecimal("0.02"), usage.reload.web_search_cost
  end

  test "#estimated_cost should include fixed search content blocks for gpt-4.1-mini" do
    model = create(:llm_model, model_id: "gpt-4.1-mini", pricing: { text_tokens: { standard: { input_per_million: 0.4 } } })
    RubyLLM.models.load_from_store
    usage = create(:ruby_llm_usage, chat: nil, model: model.model_id, server_tool_use: { "web_search_requests" => 2 })

    assert_equal BigDecimal("0.0264"), usage.reload.web_search_cost
    assert_equal BigDecimal("0.0564"), usage.estimated_cost

    model.update!(pricing: { text_tokens: { standard: { input_per_million: 9 } } })
    RubyLLM.models.load_from_store
    assert_equal BigDecimal("0.0564"), usage.reload.estimated_cost
  end

  test "#estimated_cost should recognize dated gpt-4o-mini models" do
    model = create(:llm_model, model_id: "gpt-4o-mini-2024-07-18",
                              pricing: { text_tokens: { standard: { input_per_million: 0.15 } } })
    RubyLLM.models.load_from_store
    usage = create(:ruby_llm_usage, chat: nil, model: model.model_id, server_tool_use: { "web_search_requests" => 1 })

    assert_equal BigDecimal("0.0112"), usage.reload.web_search_cost
  end

  test "#estimated_cost should remain unknown when fixed search content pricing is missing" do
    model = create(:llm_model, model_id: "gpt-4.1-mini")
    RubyLLM.models.load_from_store
    usage = create(:ruby_llm_usage, chat: nil, model: model.model_id, server_tool_use: { "web_search_requests" => 2 })

    assert_nil usage.reload.web_search_cost
    assert_nil usage.estimated_cost
    assert_equal BigDecimal("0.03"), usage.total_cost
  end

  test "#estimated_cost should retain search spend when token costs are unknown" do
    usage = create(:ruby_llm_usage, total_cost: nil, status: "cancelled", server_tool_use: { "web_search_requests" => 2 })

    assert_equal BigDecimal("0.02"), usage.reload.web_search_cost
    assert_nil usage.estimated_cost
    totals = LlmUsageReport.new(chats: LlmChat.where(id: usage.chat_id)).totals
    assert_equal BigDecimal("0.02"), totals.known_cost
    assert_nil totals.total_cost
  end

  test "#estimated_cost should leave provider-inclusive totals unchanged" do
    usage = create(:ruby_llm_usage, provider: "openrouter", server_tool_use: { "web_search_requests" => 2 })

    assert_equal 0, usage.reload.web_search_cost
    assert_equal BigDecimal("0.03"), usage.estimated_cost
  end

  test "#estimated_cost should not charge for zero searches or other tools" do
    usage = create(:ruby_llm_usage, server_tool_use: { "web_search_requests" => 0, "code_execution_requests" => 2 })

    assert_equal 0, usage.reload.web_search_cost
    assert_equal BigDecimal("0.03"), usage.estimated_cost
  end
end
