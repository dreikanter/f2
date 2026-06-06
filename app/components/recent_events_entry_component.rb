class RecentEventsEntryComponent < ViewComponent::Base
  include EventLogEntryPresentation

  def initialize(event:, href:)
    @event = event
    @href = href
  end

  def call
    content_tag(:li, class: "flex items-center gap-3 px-4 py-2.5",
                     data: { key: "recent_events.#{event.id}" }) do
      safe_join([badge_tag, description_tag, posts_count_tag, time_tag].compact)
    end
  end

  private

  attr_reader :event, :href

  def badge_tag
    render(BadgeComponent.new(text: event.level.humanize, color: badge_color(event.level)))
  end

  def description_tag
    content_tag(:span, render(EventDescriptionComponent.new(event: event)),
                class: "flex-1 truncate text-sm text-slate-700",
                data: { key: "recent_events.description" })
  end

  def posts_count_tag
    return unless event.type == "feed_refresh"

    count = event.imported_posts_count
    return if count.zero?

    content_tag(:span, helpers.pluralize(count, "post"),
                class: "shrink-0 text-slate-400",
                data: { key: "recent_events.posts_count" })
  end

  def time_tag
    link_to(helpers.short_time_ago(event.created_at), href,
            class: "shrink-0 text-xs font-medium text-slate-500 hover:text-slate-700",
            title: event.created_at.rfc3339,
            data: { key: "recent_events.timestamp" })
  end
end
