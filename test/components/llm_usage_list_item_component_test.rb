require "test_helper"
require "view_component/test_case"

class LlmUsageListItemComponentTest < ViewComponent::TestCase
  def usage
    @usage ||= create(:llm_usage, model: "claude-sonnet-4-6", stage: :loader,
                                  input_tokens: 1_000, output_tokens: 500, cost_estimate_cents: 3)
  end

  def render_usage(record = usage)
    render_inline(LlmUsageListItemComponent.new(usage: record))
  end

  test "#render should show the model and stage" do
    result = render_usage

    assert_equal "claude-sonnet-4-6", result.css("[data-key='events.llm_usage.model']").text
    assert_equal "loader", result.css("[data-key='events.llm_usage.stage']").text
  end

  test "#render should summarize input and output tokens" do
    result = render_usage

    tokens = result.css("[data-key='events.llm_usage.tokens']").text
    assert_equal "1,000 in · 500 out", tokens
  end

  test "#render should append cached tokens only when the call reused cache" do
    cached = create(:llm_usage, input_tokens: 10, output_tokens: 5,
                                cache_read_tokens: 200, cache_write_tokens: 40)

    result = render_usage(cached)

    assert_equal "10 in · 5 out · 240 cached", result.css("[data-key='events.llm_usage.tokens']").text
  end

  test "#render should format the call cost as currency" do
    result = render_usage

    assert_equal "$0.03", result.css("[data-key='events.llm_usage.cost']").text
  end

  test "#render should badge a successful outcome" do
    result = render_usage

    assert_equal "Success", result.css("[data-key='events.llm_usage.outcome']").text
  end

  test "#render should badge a failed outcome" do
    failed = create(:llm_usage, outcome: :provider_error)

    result = render_usage(failed)

    assert_equal "Provider error", result.css("[data-key='events.llm_usage.outcome']").text
  end
end
