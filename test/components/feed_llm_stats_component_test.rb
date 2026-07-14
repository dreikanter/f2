require "test_helper"
require "view_component/test_case"

class FeedLlmStatsComponentTest < ViewComponent::TestCase
  def feed
    @feed ||= create(:feed)
  end

  def feed_with_usages
    @feed_with_usages ||= create(:feed).tap do |current_feed|
      create(:llm_usage, feed: current_feed, user: current_feed.user,
                         cost_estimate_cents: 25, input_tokens: 10_000, output_tokens: 5_000)
      create(:llm_usage, feed: current_feed, user: current_feed.user,
                         cost_estimate_cents: 15, input_tokens: 8_000, output_tokens: 2_000)
      credential = create(:search_credential, :active, user: current_feed.user)
      2.times do
        refresh = Event.create!(type: "feed_refresh", level: :info,
                                subject: current_feed, user: current_feed.user)
        WebSearchUsage.record!(credential: credential, refresh_event: refresh)
      end
    end
  end

  test "#render should display AI call count" do
    result = render_inline(FeedLlmStatsComponent.new(feed: feed_with_usages))

    value = result.css('[data-key="llm_stats.ai_calls.value"]').first
    assert_not_nil value
    assert_equal "2", value.text.strip
  end

  test "#render should display estimated AI spend" do
    result = render_inline(FeedLlmStatsComponent.new(feed: feed_with_usages))

    value = result.css('[data-key="llm_stats.estimated_spend.value"]').first
    assert_not_nil value
    assert_equal "$0.40", value.text.strip
  end

  test "#render should display search calls and fractional estimated spend" do
    result = render_inline(FeedLlmStatsComponent.new(feed: feed_with_usages))

    assert_equal "2", result.css('[data-key="llm_stats.search_calls.value"]').first.text.strip
    assert_equal "$0.00200", result.css('[data-key="llm_stats.search_estimated_spend.value"]').first.text.strip
  end

  test "#render should exclude AI and search usages older than the stats period" do
    create(:llm_usage, feed: feed_with_usages, user: feed_with_usages.user,
                       cost_estimate_cents: 100, created_at: LlmUsage::STATS_PERIOD.ago - 1.day)
    credential = create(:search_credential, :active, user: feed_with_usages.user, display_name: "Old search")
    travel_to(WebSearchUsage::STATS_PERIOD.ago - 1.day) do
      refresh = Event.create!(type: "feed_refresh", level: :info,
                              subject: feed_with_usages, user: feed_with_usages.user)
      WebSearchUsage.record!(credential: credential, refresh_event: refresh)
    end

    result = render_inline(FeedLlmStatsComponent.new(feed: feed_with_usages))

    assert_equal "2", result.css('[data-key="llm_stats.ai_calls.value"]').first.text.strip
    assert_equal "$0.40", result.css('[data-key="llm_stats.estimated_spend.value"]').first.text.strip
    assert_equal "2", result.css('[data-key="llm_stats.search_calls.value"]').first.text.strip
    assert_equal "$0.00200", result.css('[data-key="llm_stats.search_estimated_spend.value"]').first.text.strip
  end

  test "#render should include mobile layout with full labels" do
    result = render_inline(FeedLlmStatsComponent.new(feed: feed))

    assert_not_nil result.css(".md\\:hidden").first
    assert_equal "AI calls (last 30 days)", result.css('.md\\:hidden [data-key="llm_stats.ai_calls.label"]').first.text
    assert_equal "Estimated AI spend (last 30 days)", result.css('.md\\:hidden [data-key="llm_stats.estimated_spend.label"]').first.text
    assert_equal "Search calls (last 30 days)", result.css('.md\\:hidden [data-key="llm_stats.search_calls.label"]').first.text
    assert_equal "Estimated search spend (last 30 days)", result.css('.md\\:hidden [data-key="llm_stats.search_estimated_spend.label"]').first.text
  end

  test "#render should include desktop layout with short labels" do
    result = render_inline(FeedLlmStatsComponent.new(feed: feed))

    assert_not_nil result.css(".hidden.md\\:flex").first
    assert_equal "AI calls (30 days)", result.css('.hidden.md\\:flex [data-key="llm_stats.ai_calls.label"]').first.text
    assert_equal "AI spend (30 days)", result.css('.hidden.md\\:flex [data-key="llm_stats.estimated_spend.label"]').first.text
    assert_equal "Search calls (30 days)", result.css('.hidden.md\\:flex [data-key="llm_stats.search_calls.label"]').first.text
    assert_equal "Search spend (30 days)", result.css('.hidden.md\\:flex [data-key="llm_stats.search_estimated_spend.label"]').first.text
  end

  test "#render should show zero when no usages" do
    result = render_inline(FeedLlmStatsComponent.new(feed: feed))

    assert_equal "0", result.css('[data-key="llm_stats.ai_calls.value"]').first.text.strip
    assert_equal "$0.00", result.css('[data-key="llm_stats.estimated_spend.value"]').first.text.strip
    assert_equal "0", result.css('[data-key="llm_stats.search_calls.value"]').first.text.strip
    assert_equal "$0.00000", result.css('[data-key="llm_stats.search_estimated_spend.value"]').first.text.strip
  end
end
