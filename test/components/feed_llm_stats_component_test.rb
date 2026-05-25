require "test_helper"
require "view_component/test_case"

class FeedLlmStatsComponentTest < ViewComponent::TestCase
  def feed
    @feed ||= create(:feed)
  end

  def feed_with_usages
    @feed_with_usages ||= create(:feed).tap do |f|
      create(:llm_usage, feed: f, user: f.user, cost_estimate_cents: 25, input_tokens: 10_000, output_tokens: 5_000)
      create(:llm_usage, feed: f, user: f.user, cost_estimate_cents: 15, input_tokens: 8_000, output_tokens: 2_000)
    end
  end

  test "#render should display AI call count" do
    result = render_inline(FeedLlmStatsComponent.new(feed: feed_with_usages))

    value = result.css('[data-key="llm_stats.ai_calls.value"]').first
    assert_not_nil value
    assert_equal "2", value.text.strip
  end

  test "#render should display estimated spend" do
    result = render_inline(FeedLlmStatsComponent.new(feed: feed_with_usages))

    value = result.css('[data-key="llm_stats.estimated_spend.value"]').first
    assert_not_nil value
    assert_equal "$0.40", value.text.strip
  end

  test "#render should include mobile layout with full labels" do
    result = render_inline(FeedLlmStatsComponent.new(feed: feed))

    assert_not_nil result.css(".md\\:hidden").first
    assert_equal "AI calls", result.css(".md\\:hidden [data-key=\"llm_stats.ai_calls.label\"]").first.text
    assert_equal "Estimated spend", result.css(".md\\:hidden [data-key=\"llm_stats.estimated_spend.label\"]").first.text
  end

  test "#render should include desktop layout with short labels" do
    result = render_inline(FeedLlmStatsComponent.new(feed: feed))

    assert_not_nil result.css(".hidden.md\\:flex").first
    assert_equal "AI calls", result.css(".hidden.md\\:flex [data-key=\"llm_stats.ai_calls.label\"]").first.text
    assert_equal "Spend", result.css(".hidden.md\\:flex [data-key=\"llm_stats.estimated_spend.label\"]").first.text
  end

  test "#render should show zero when no usages" do
    result = render_inline(FeedLlmStatsComponent.new(feed: feed))

    calls_value = result.css('[data-key="llm_stats.ai_calls.value"]').first.text.strip
    assert_equal "0", calls_value

    spend_value = result.css('[data-key="llm_stats.estimated_spend.value"]').first.text.strip
    assert_equal "$0.00", spend_value
  end
end
