class EventLogComponent < ViewComponent::Base
  def initialize(events:, endpoint:, path_builder:, dom_id:, admin: false)
    @events = events
    @endpoint = endpoint
    @path_builder = path_builder
    @dom_id = dom_id
    @admin = admin
  end

  def call
    content_tag(:div, class: "space-y-3", id: dom_id, data: host_data) do
      safe_join([refresh_button, events_body])
    end
  end

  private

  attr_reader :events, :endpoint, :path_builder, :dom_id

  def host_data
    {
      controller: "polling",
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
    if events.any?
      content_tag(:div, class: "space-y-3", data: { key: "events.list" }) do
        safe_join(events.map { |event| event_card(event) })
      end
    else
      render EmptyStateComponent.new("No events to show yet")
    end
  end

  def event_card(event)
    render CardComponent.new(href: path_builder.call(event), class: "p-4", data: { key: "events.#{event.id}" }) do
      content_tag(:div, class: "flex items-start justify-between gap-4") do
        safe_join([event_summary(event), event_time(event)])
      end
    end
  end

  def event_summary(event)
    content_tag(:div, class: "min-w-0 space-y-1") do
      safe_join([
        content_tag(:div, class: "flex flex-wrap items-center gap-2") do
          safe_join([
            render(BadgeComponent.new(text: event.level.humanize, color: badge_color(event.level))),
            content_tag(:code, event.type, class: "text-sm font-semibold text-slate-800", data: { key: "events.type" })
          ])
        end,
        content_tag(:div, class: "truncate text-sm text-slate-600") do
          render EventDescriptionComponent.new(event: event)
        end,
        event_context(event)
      ])
    end
  end

  def event_context(event)
    parts = []
    parts << user_label(event) if event.user_id.present? || @admin
    parts << subject_label(event)

    content_tag(:div, helpers.safe_join(parts.compact, " • "), class: "text-xs text-slate-500") if parts.any?
  end

  def user_label(event)
    if event.user_id.present?
      if @admin
        helpers.link_to("User ##{event.user_id}", helpers.admin_events_path(filter: { user_id: event.user_id }), class: "hover:text-slate-700", data: { key: "events.user" })
      else
        helpers.tag.span("User ##{event.user_id}", data: { key: "events.user" })
      end
    else
      helpers.tag.em("System", data: { key: "events.user" })
    end
  end

  def subject_label(event)
    return if event.subject_type.blank?

    value = event.subject_id.present? ? "#{event.subject_type} ##{event.subject_id}" : event.subject_type
    helpers.tag.span(value, data: { key: "events.subject" })
  end

  def event_time(event)
    content_tag(:span, helpers.short_time_ago(event.created_at), class: "shrink-0 text-xs font-medium text-slate-500", title: event.created_at.rfc3339, data: { key: "events.timestamp" })
  end

  def last_event_id
    events.map(&:id).max || 0
  end

  def badge_color(level)
    case level
    when "debug" then :gray
    when "info" then :blue
    when "warning" then :yellow
    when "error" then :red
    else :blue
    end
  end
end
