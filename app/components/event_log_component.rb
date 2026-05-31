class EventLogComponent < ViewComponent::Base
  # Stable id used as the Turbo Stream replace target. The log is never rendered
  # more than once per page, so a constant is enough.
  DOM_ID = "events_log".freeze

  renders_many :entries

  # `endpoint` enables polling (first page only). `older_url`/`newer_url` enable
  # cursor pagination links; omit them for an unpaginated log.
  def initialize(events:, endpoint: nil, older_url: nil, newer_url: nil)
    @events = events
    @endpoint = endpoint
    @older_url = older_url
    @newer_url = newer_url
  end

  def call
    content_tag(:div, class: "space-y-3", id: DOM_ID, data: host_data) do
      safe_join([refresh_button, events_body, pagination_nav].compact)
    end
  end

  private

  attr_reader :events, :endpoint

  def polling?
    endpoint.present?
  end

  def host_data
    data = { key: "events.log" }
    return data unless polling?

    data.merge(
      controller: "polling",
      polling_endpoint_value: endpoint,
      polling_interval_value: 10_000,
      polling_initial_delay_value: 10_000,
      polling_max_polls_value: 0,
      last_event_id: last_event_id
    )
  end

  def refresh_button
    return unless polling?

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

  def pagination_nav
    return if @older_url.blank? && @newer_url.blank?

    content_tag(:nav, class: "flex items-center justify-between gap-3", aria: { label: "Events pagination" }, data: { key: "events.pagination" }) do
      safe_join([newer_link, older_link])
    end
  end

  def newer_link
    nav_link("← Newer", @newer_url, "events.newer")
  end

  def older_link
    nav_link("Older →", @older_url, "events.older")
  end

  def nav_link(label, url, key)
    classes = "inline-flex items-center justify-center whitespace-nowrap rounded-md border border-slate-200 bg-white px-4 py-2 text-sm font-semibold text-slate-600 shadow-sm transition hover:bg-slate-50"

    if url
      link_to(label, url, class: classes, data: { key: key })
    else
      content_tag(:span, label, class: "#{classes} text-slate-300 cursor-not-allowed")
    end
  end

  def last_event_id
    events.map(&:id).max || 0
  end
end
