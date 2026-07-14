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

  test "#render should exclude usages older than the stats period" do
    create(:llm_usage, feed: feed_with_usages, user: feed_with_usages.user,
           cost_estimate_cents: 100, created_at: LlmUsage::STATS_PERIOD.ago - 1.day)

    result = render_inline(FeedLlmStatsComponent.new(feed: feed_with_usages))

    assert_equal "2", result.css('[data-key="llm_stats.ai_calls.value"]').first.text.strip
    assert_equal "$0.40", result.css('[data-key="llm_stats.estimated_spend.value"]').first.text.strip
  end

  test "#render should include mobile layout with full labels" do
    result = render_inline(FeedLlmStatsComponent.new(feed: feed))

    assert_not_nil result.css(".md\\:hidden").first
    assert_equal "AI calls (last 30 days)", result.css(".md\\:hidden [data-key=\"llm_stats.ai_calls.label\"]").first.text
    assert_equal "Estimated spend (last 30 days)", result.css(".md\\:hidden [data-key=\"llm_stats.estimated_spend.label\"]").first.text
  end

  test "#render should include desktop layout with short labels" do
    result = render_inline(FeedLlmStatsComponent.new(feed: feed))

    assert_not_nil result.css(".hidden.md\\:flex").first
    assert_equal "AI calls (30 days)", result.css(".hidden.md\\:flex [data-key=\"llm_stats.ai_calls.label\"]").first.text
    assert_equal "Spend (30 days)", result.css(".hidden.md\\:flex [data-key=\"llm_stats.estimated_spend.label\"]").first.text
  end

  test "#render should show zero when no usages" do
    result = render_inline(FeedLlmStatsComponent.new(feed: feed))

    calls_value = result.css('[data-key="llm_stats.ai_calls.value"]').first.text.strip
    assert_equal "0", calls_value

    spend_value = result.css('[data-key="llm_stats.estimated_spend.value"]').first.text.strip
    assert_equal "$0.00", spend_value

    searches_value = result.css('[data-key="llm_stats.search_calls.value"]').first.text.strip
    assert_equal "0", searches_value
  end

  def record_search_calls(feed, count, at: 1.hour.ago, provider: "serper")
    credential = create(:search_credential, :active, user: feed.user, provider: provider,
                                                     display_name: "#{provider} #{feed.id}")
    count.times do
      create(:event, type: "web_search", level: :debug, subject: credential, user: feed.user,
                     metadata: { "provider" => provider, "feed_id" => feed.id, "outcome" => "success" },
                     created_at: at)
    end
  end

  test "#render should count the feed's searches and fold their cost into spend" do
    record_search_calls(feed_with_usages, 10)

    result = render_inline(FeedLlmStatsComponent.new(feed: feed_with_usages))

    assert_equal "10", result.css('[data-key="llm_stats.search_calls.value"]').first.text.strip
    assert_equal "$0.41", result.css('[data-key="llm_stats.estimated_spend.value"]').first.text.strip
  end

  test "#render should exclude search calls outside the stats period and from other feeds" do
    record_search_calls(feed_with_usages, 10, at: LlmUsage::STATS_PERIOD.ago - 1.day)
    record_search_calls(feed, 3)

    result = render_inline(FeedLlmStatsComponent.new(feed: feed_with_usages))

    assert_equal "0", result.css('[data-key="llm_stats.search_calls.value"]').first.text.strip
    assert_equal "$0.40", result.css('[data-key="llm_stats.estimated_spend.value"]').first.text.strip
  end
end
