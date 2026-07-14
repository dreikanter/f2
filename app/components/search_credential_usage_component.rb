# Time-scoped search API call counts with estimated cost for one credential,
# fed by the per-call "web_search" events. Windows stay inside event
# retention (1 month), so the numbers can't silently shrink the way an
# all-time total would (spec 006 §6).
class SearchCredentialUsageComponent < ViewComponent::Base
  WINDOWS = [
    { label: "Last 24 hours", duration: 24.hours, key: "day" },
    { label: "Last 7 days", duration: 7.days, key: "week" },
    { label: "Last 30 days", duration: 30.days, key: "month" }
  ].freeze

  def initialize(search_credential:)
    @search_credential = search_credential
  end

  def call
    render(ListComponent.new) do |list|
      WINDOWS.each do |window|
        list.with_item(StatListItemComponent.new(
          label: window[:label],
          value: formatted_usage(call_count(window[:duration])),
          key: "search_credential.usage.#{window[:key]}"
        ))
      end
    end
  end

  private

  def call_count(duration)
    Event.for_subject(@search_credential)
         .where(type: "web_search")
         .where(created_at: duration.ago..)
         .count
  end

  # Counts include failed calls, and the estimate bills them all — erring
  # toward overstating an estimate rather than hiding spend.
  def formatted_usage(count)
    cents = WebSearchProvider.estimated_cost_cents(@search_credential.provider, count)
    "#{helpers.pluralize(count, 'search')} · ~#{helpers.number_to_currency(cents / 100.0)}"
  end
end
