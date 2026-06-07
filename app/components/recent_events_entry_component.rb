class RecentEventsEntryComponent < ViewComponent::Base
  include EventLogEntryPresentation

  def initialize(event:, href:)
    @event = event
    @href = href
  end

  def call
    content_tag(:li, class: "flex items-center gap-3 px-4 py-2.5",
                     data: { key: "recent_events.#{event.id}" }) do
      safe_join([time_tag, severity_dot, description_tag].compact)
    end
  end

  private

  attr_reader :event, :href

  def description_tag
    content_tag(:span, render(EventDescriptionComponent.new(event: event)),
                class: "flex-1 truncate text-sm text-slate-700",
                data: { key: "recent_events.description" })
  end

  def time_tag
    link_to(helpers.short_time_ago(event.created_at), href,
            class: "w-10 shrink-0 text-xs font-medium tabular-nums text-slate-400 hover:text-slate-700",
            title: event.created_at.rfc3339,
            data: { key: "recent_events.timestamp" })
  end
end
