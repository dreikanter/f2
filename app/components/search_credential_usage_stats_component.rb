class SearchCredentialUsageStatsComponent < ViewComponent::Base
  PERIOD_LABELS = {
    day: "today",
    week: "past 7 days",
    month: "past 30 days"
  }.freeze

  def initialize(search_credential:)
    @search_credential = search_credential
  end

  def call
    render(ListComponent.new) do |list|
      items.each { list.with_item(StatListItemComponent.new(**_1)) }
    end
  end

  private

  def items
    usage_counts.flat_map do |period, count|
      label = PERIOD_LABELS.fetch(period)
      [
        {
          label: "Search calls, #{label}",
          value: helpers.number_with_delimiter(count),
          key: "search_credential.usage.#{period}.calls"
        },
        {
          label: "Estimated spend, #{label}",
          value: formatted_cost(count),
          key: "search_credential.usage.#{period}.cost"
        }
      ]
    end
  end

  def usage_counts
    @usage_counts ||= WebSearchUsage.counts_for_periods(@search_credential)
  end

  def formatted_cost(count)
    cents = @search_credential.estimated_search_cost_cents(count)
    helpers.number_to_currency(cents / 100, precision: 5)
  end
end
