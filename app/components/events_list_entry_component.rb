class EventsListEntryComponent < ViewComponent::Base
  include EventLogEntryPresentation

  def initialize(event:, href:)
    @event = event
    @href = href
  end

  def call
    content_tag(:li, class: "flex items-center gap-3 px-4 py-2.5",
                     data: { key: "events.entry", event_type: event.type, event_id: event.id }) do
      safe_join([severity_tag, description_tag, time_tag])
    end
  end

  private

  attr_reader :event, :href

  # A fixed-width gutter keeps the message left edge aligned whether or not the
  # entry carries a severity icon.
  def severity_tag
    icon = severity_icon
    content_tag(:span, icon, class: "flex w-4 shrink-0 items-center justify-center",
                             data: icon ? { key: "events.severity" } : {})
  end

  def description_tag
    content_tag(:span, render(EventDescriptionComponent.for(event)),
                class: "min-w-0 flex-1 truncate text-slate-700",
                data: { key: "events.description" })
  end

  def time_tag
    link_to(helpers.short_time_ago(event.created_at), href,
            class: "shrink-0 text-sm font-medium tabular-nums text-slate-400 hover:text-slate-700",
            title: event.created_at.rfc3339,
            data: { key: "events.timestamp" })
  end
end
