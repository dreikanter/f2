class EventLogComponent < ViewComponent::Base
  # Stable id used as the Turbo Stream replace target. The log is never rendered
  # more than once per page, so a constant is enough.
  DOM_ID = "events_log".freeze

  renders_many :entries

  # `endpoint` enables polling (first page only). `older_url`/`newer_url` enable
  # cursor pagination links; omit them for an unpaginated log. Renders entries as
  # a stack of cards; this is the admin events log. The user-facing log uses
  # EventsListComponent instead.
  def initialize(events:, endpoint: nil, older_url: nil, newer_url: nil)
    @events = events
    @endpoint = endpoint
    @older_url = older_url
    @newer_url = newer_url
  end

  def call
    content_tag(:div, class: "space-y-3", id: DOM_ID, data: host_data) do
      safe_join([events_body, pagination_nav].compact)
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
      # The log stays interactive while it polls, so it must not be marked
      # aria-busy (which globally disables pointer events).
      polling_indicate_busy_value: false,
      last_event_id: last_event_id
    )
  end

  def events_body
    return render(EmptyStateComponent.new("No events to show yet")) unless entries.any?

    content_tag(:div, class: "space-y-3", data: { key: "events.list" }) do
      safe_join(entries)
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
    classes = "inline-flex items-center justify-center whitespace-nowrap rounded-md border border-slate-200 bg-white px-4 py-2 text-sm font-semibold text-slate-600 shadow-sm transition"

    if url
      link_to(label, url, class: "#{classes} hover:bg-slate-50", data: { key: key })
    else
      content_tag(:span, label, class: "#{classes} opacity-50 cursor-not-allowed", data: { key: key })
    end
  end

  def last_event_id
    events.map(&:id).max || 0
  end
end
