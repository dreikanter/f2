# Feed-level summary of recent AI and web-search activity, combining stored
# request counts and cost estimates for the feed's statistics panel.
class FeedLlmStatsComponent < StatsPanelComponent
  def initialize(feed:, totals:)
    @feed = feed
    @totals = totals
  end

  def call
    safe_join([super, cost_note].compact)
  end

  private

  attr_reader :totals

  def key_prefix
    "llm_stats"
  end

  def layout_items
    @layout_items ||= [
      {
        key: "ai_calls",
        label: "AI calls (last #{period_in_days} days)",
        label_short: "AI calls (#{period_in_days} days)",
        value: helpers.number_with_delimiter(totals.call_count)
      },
      {
        key: "estimated_spend",
        label: "Estimated AI spend (last #{period_in_days} days)",
        label_short: "AI spend (#{period_in_days} days)",
        value: formatted_cost
      },
      {
        key: "search_calls",
        label: "Search calls (last #{period_in_days} days)",
        label_short: "Search calls (#{period_in_days} days)",
        value: helpers.number_with_delimiter(search_call_count)
      },
      {
        key: "search_estimated_spend",
        label: "Estimated search spend (last #{period_in_days} days)",
        label_short: "Search spend (#{period_in_days} days)",
        value: formatted_search_cost
      }
    ]
  end

  def web_search_events
    @web_search_events ||= WebSearchUsage.for_feed(@feed).to_a
  end

  def search_call_count
    web_search_events.size
  end

  def search_cost_cents
    @search_cost_cents ||= WebSearchUsage.estimated_cost_cents(web_search_events)
  end

  def period_in_days
    LlmUsageReport::STATS_PERIOD.in_days.to_i
  end

  def formatted_cost
    return "Unknown" if totals.incomplete?

    helpers.number_to_currency(totals.total_cost)
  end

  def cost_note
    return unless totals.incomplete?

    text = "Some AI or built-in search costs couldn’t be estimated."
    if totals.known_cost.positive?
      text += " Available estimates total #{helpers.number_to_currency(totals.known_cost)}."
    end
    tag.p(text, class: "mt-2 text-sm text-muted", data: { key: "llm_stats.cost_note" })
  end

  def formatted_search_cost
    helpers.number_to_currency(search_cost_cents / 100, precision: 5)
  end
end
