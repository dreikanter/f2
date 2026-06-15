# User-facing summary of a single event, rendered as a stat list on the event
# page. Mirrors the admin EventDetailsComponent, but stays lean: it skips the
# admin-only fields and links. Feed refresh events also surface how many posts
# were imported and how long the refresh took.
class EventStatsComponent < ViewComponent::Base
  def initialize(event:)
    @event = event
  end

  def call
    render(ListComponent.new) do |list|
      add_type_item(list)
      add_level_item(list)
      add_subject_item(list)
      add_created_item(list)
      add_feed_refresh_items(list) if feed_refresh?
    end
  end

  private

  def add_type_item(component)
    component.with_item(ListComponent::StatItemComponent.new(
      label: "Type",
      value: helpers.tag.code(@event.type, class: "text-sm", data: { key: "events.type" })
    ))
  end

  def add_level_item(component)
    component.with_item(ListComponent::StatItemComponent.new(
      label: "Level",
      value: @event.level.capitalize
    ))
  end

  def add_subject_item(component)
    return unless @event.subject_type.present?

    subject_value = if @event.subject_id.present?
      "#{@event.subject_type} ##{@event.subject_id}"
    else
      @event.subject_type
    end

    component.with_item(ListComponent::StatItemComponent.new(
      label: "Subject",
      value: subject_value
    ))
  end

  def add_created_item(component)
    value = helpers.safe_join([
      helpers.long_time_tag(@event.created_at),
      " ",
      helpers.tag.span("(#{helpers.short_time_ago(@event.created_at)})", class: "text-slate-500")
    ])

    component.with_item(ListComponent::StatItemComponent.new(
      label: "Created",
      value: value
    ))
  end

  def add_feed_refresh_items(component)
    if new_posts.present?
      component.with_item(ListComponent::StatItemComponent.new(
        label: "New posts",
        value: new_posts,
        key: "events.new_posts"
      ))
    end

    if total_duration.present?
      component.with_item(ListComponent::StatItemComponent.new(
        label: "Duration",
        value: format_duration(total_duration),
        key: "events.duration"
      ))
    end
  end

  # Refreshes usually finish in seconds, so a coarse "less than a minute" reads
  # as a non-answer. Show precise seconds, rolling up to minutes when it runs long.
  def format_duration(seconds)
    return "#{seconds.round(1)}s" if seconds < 60

    minutes = (seconds / 60).floor
    remaining = (seconds % 60).round

    "#{minutes}m #{remaining}s"
  end

  def feed_refresh?
    @event.type == "feed_refresh"
  end

  def stats
    @event.metadata.fetch("stats", {})
  end

  def new_posts
    stats["new_posts"]
  end

  def total_duration
    stats["total_duration"]
  end
end
