require "test_helper"

class LlmClient::ToolBudgetTest < ActiveSupport::TestCase
  def budget(rounds: 2, grace: 1)
    @budget ||= LlmClient::ToolBudget.new(rounds: rounds, grace: grace)
  end

  test "#claim should allow work while the budget lasts" do
    assert_nil budget.claim
    assert_nil budget.claim
    assert_equal 2, budget.spent
  end

  test "#claim should tell the model to answer once the budget is spent" do
    2.times { budget.claim }

    assert_equal({ error: LlmClient::ToolBudget::OVER_BUDGET }, budget.claim)
  end

  test "#claim should halt the loop when the model keeps calling past the grace" do
    3.times { budget.claim }

    halt = budget.claim
    assert_instance_of RubyLLM::Tool::Halt, halt
    assert_equal LlmClient::ToolBudget::HALTED, halt.content
  end

  test "#claim should keep halting once halted" do
    5.times { budget.claim }

    assert_instance_of RubyLLM::Tool::Halt, budget.claim
  end

  test "the shared budget should count both tools together" do
    shared = LlmClient::ToolBudget.new(rounds: 1, grace: 0)
    search = LlmClient::Tools::WebSearch.new(provider: nil, credential: nil, budget: shared)
    fetch = LlmClient::Tools::WebFetch.new(budget: shared)

    assert_nil shared.claim
    assert_instance_of RubyLLM::Tool::Halt, fetch.execute(url: "https://example.com/")
    assert_equal({ error: "Refused: query must not be blank." }, search.execute(query: ""))
  end
end
