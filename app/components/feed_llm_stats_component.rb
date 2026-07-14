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
        key: "search_calls",
        label: "Searches (last #{period_in_days} days)",
        label_short: "Searches (#{period_in_days} days)",
        value: helpers.number_with_delimiter(search_call_count)
      },
      {
        key: "estimated_spend",
        label: "Estimated spend (last #{period_in_days} days)",
        label_short: "Spend (#{period_in_days} days)",
        value: formatted_cost
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

  # Per-call "web_search" events carry the feed in metadata (their subject is
  # the credential), so the feed scope goes through jsonb. Grouping by
  # provider keeps the cost estimate right across credential switches.
  def search_counts_by_provider
    @search_counts_by_provider ||=
      Event.web_search
           .attributed_to_feed(@feed)
           .where(created_at: LlmUsage::STATS_PERIOD.ago..)
           .group(Arel.sql("metadata->>'provider'"))
           .count
  end

  def search_call_count
    search_counts_by_provider.values.sum
  end

  def search_cost_cents
    search_counts_by_provider.sum do |provider, count|
      WebSearchProvider.estimated_cost_cents(provider, count)
    end
  end

  def period_in_days
    LlmUsage::STATS_PERIOD.in_days.to_i
  end

  # One spend figure for the whole run pipeline: LLM tokens plus estimated
  # search fees — users think "what did this feed cost", not per-subsystem.
  def formatted_cost
    helpers.number_to_currency((total_cost_cents + search_cost_cents) / 100.0)
  end
end
