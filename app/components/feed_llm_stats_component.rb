class FeedLlmStatsComponent < StatsPanelComponent
  def initialize(feed:)
    @feed = feed
  end

  def call
    safe_join([super, cost_note].compact)
  end

  private

  def key_prefix
    "llm_stats"
  end

  def layout_items
    @layout_items ||= [
      {
        key: "ai_calls",
        label: "AI calls (last #{period_in_days} days)",
        label_short: "AI calls (#{period_in_days} days)",
        value: helpers.number_with_delimiter(call_count)
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

  def call_count
    @call_count ||= usages.count
  end

  def total_cost_cents
    @total_cost_cents ||= usages.sum(:cost_estimate_cents)
  end

  def usages
    @feed.llm_usages.within_stats_period
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
    LlmUsage::STATS_PERIOD.in_days.to_i
  end

  def formatted_cost
    return "Unknown" if unknown_cost?

    helpers.number_to_currency(total_cost_cents / 100.0)
  end

  def unknown_cost?
    return @unknown_cost unless @unknown_cost.nil?

    @unknown_cost = usages.where(cost_estimate_cents: nil).exists?
  end

  def cost_note
    return unless unknown_cost?

    text = "Some AI or built-in search costs couldn’t be estimated."
    if total_cost_cents.positive?
      text += " Available estimates total #{helpers.number_to_currency(total_cost_cents / 100.0)}."
    end
    tag.p(text, class: "mt-2 text-sm text-muted", data: { key: "llm_stats.cost_note" })
  end

  def formatted_search_cost
    helpers.number_to_currency(search_cost_cents / 100, precision: 5)
  end
end
