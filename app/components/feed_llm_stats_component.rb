class FeedLlmStatsComponent < ViewComponent::Base
  def initialize(feed:)
    @feed = feed
  end

  def call
    tag.div { safe_join([mobile_layout, desktop_layout]) }
  end

  private

  def mobile_layout
    render(DescriptionListComponent.new(css_class: class_names("md:hidden", DescriptionListComponent::DEFAULT_CSS_CLASSES))) do |list|
      layout_items.each { |item| list.with_item(mobile_stat_cell(item)) }
    end
  end

  def desktop_layout
    render(StatsBarComponent.new(css_class: class_names("hidden", StatsBarComponent::DEFAULT_CSS_CLASSES))) do |bar|
      layout_items.each { |item| bar.with_item(desktop_stat_cell(item)) }
    end
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

  def mobile_stat_cell(item)
    StatListItemComponent.new(
      label: item[:label],
      value: item[:value],
      key: "llm_stats.#{item[:key]}"
    )
  end

  def desktop_stat_cell(item)
    StatBarItemComponent.new(
      label: item[:label_short],
      value: item[:value],
      key: "llm_stats.#{item[:key]}"
    )
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
    helpers.number_to_currency(total_cost_cents / 100.0)
  end

  def formatted_search_cost
    helpers.number_to_currency(search_cost_cents / 100, precision: 5)
  end
end
