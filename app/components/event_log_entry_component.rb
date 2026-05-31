class EventLogEntryComponent < ViewComponent::Base
  def initialize(event:, href:)
    @event = event
    @href = href
  end

  def call
    render CardComponent.new(href: @href, class: "p-4", data: { key: "events.#{event.id}" }) do
      content_tag(:div, class: "flex items-start justify-between gap-4") do
        safe_join([event_summary, event_time])
      end
    end
  end

  private

  attr_reader :event

  def event_summary
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
        event_context
      ])
    end
  end

  def event_context
    parts = []
    parts << user_label if show_user_label?
    parts << subject_label

    content_tag(:div, helpers.safe_join(parts.compact, " • "), class: "text-xs text-slate-500") if parts.any?
  end

  # Hooks overridden by the admin presentation.
  def show_user_label?
    event.user_id.present?
  end

  def user_label
    if event.user_id.present?
      helpers.tag.span("User ##{event.user_id}", data: { key: "events.user" })
    else
      helpers.tag.em("System", data: { key: "events.user" })
    end
  end

  def subject_label
    return if event.subject_type.blank?

    value = event.subject_id.present? ? "#{event.subject_type} ##{event.subject_id}" : event.subject_type
    helpers.tag.span(value, data: { key: "events.subject" })
  end

  def event_time
    content_tag(:span, helpers.short_time_ago(event.created_at), class: "shrink-0 text-xs font-medium text-slate-500", title: event.created_at.rfc3339, data: { key: "events.timestamp" })
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
