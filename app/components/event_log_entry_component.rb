class EventLogEntryComponent < ViewComponent::Base
  def initialize(event:, href:)
    @event = event
    @href = href
  end

  private

  attr_reader :event, :href

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
