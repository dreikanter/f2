class EventLogComponent < ViewComponent::Base
  # Stable id used as the Turbo Stream replace target. The log is never rendered
  # more than once per page, so a constant is enough.
  DOM_ID = "events_log".freeze

  renders_many :entries

  def initialize(events:, endpoint:)
    @events = events
    @endpoint = endpoint
  end

  def call
    content_tag(:div, class: "space-y-3", id: DOM_ID, data: host_data) do
      safe_join([refresh_button, events_body])
    end
  end

  private

  attr_reader :events, :endpoint

  def host_data
    {
      controller: "polling",
      key: "events.log",
      polling_endpoint_value: endpoint,
      polling_interval_value: 10_000,
      polling_initial_delay_value: 10_000,
      polling_max_polls_value: 0,
      last_event_id: last_event_id
    }
  end

  def refresh_button
    content_tag(:div, class: "flex justify-end") do
      button_tag(type: "button", class: "inline-flex items-center gap-2 rounded-md border border-slate-200 bg-white px-3 py-2 text-sm font-semibold text-slate-600 shadow-sm transition hover:bg-slate-50 focus:outline-none focus:ring-2 focus:ring-sky-500 focus:ring-offset-1", data: { action: "polling#refresh", key: "events.refresh" }) do
        safe_join([helpers.icon("refresh-ccw", css_class: "size-4"), "Refresh"])
      end
    end
  end

  def events_body
    if entries.any?
      content_tag(:div, class: "space-y-3", data: { key: "events.list" }) do
        safe_join(entries)
      end
    else
      render EmptyStateComponent.new("No events to show yet")
    end
  end

  def last_event_id
    events.map(&:id).max || 0
  end
end
