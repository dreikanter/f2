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
        label: "AI calls",
        label_short: "AI calls",
        value: helpers.number_with_delimiter(call_count)
      },
      {
        key: "estimated_spend",
        label: "Estimated spend",
        label_short: "Spend",
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
    @call_count ||= @feed.llm_usages.count
  end

  def total_cost_cents
    @total_cost_cents ||= @feed.llm_usages.sum(:cost_estimate_cents)
  end

  def formatted_cost
    helpers.number_to_currency(total_cost_cents / 100.0)
  end
end
