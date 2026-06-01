class RecentEventsListComponent < ViewComponent::Base
  DOM_ID = "recent_events_list".freeze

  def initialize(events:, endpoint: nil)
    @events = events
    @endpoint = endpoint
  end

  def call
    content_tag(:div, id: DOM_ID, data: host_data) do
      if @events.any?
        list = ListComponent.new
        @events.each do |event|
          list.with_item(RecentEventsEntryComponent.new(event: event, href: helpers.event_path(event)))
        end
        render(list)
      else
        render(EmptyStateComponent.new("No events to show yet"))
      end
    end
  end

  private

  def host_data
    return {} unless @endpoint.present?

    {
      controller: "polling",
      polling_endpoint_value: @endpoint,
      polling_interval_value: 10_000,
      polling_initial_delay_value: 10_000,
      polling_max_polls_value: 0,
      polling_indicate_busy_value: false,
      last_event_id: last_event_id
    }
  end

  def last_event_id
    @events.map(&:id).max || 0
  end
end
