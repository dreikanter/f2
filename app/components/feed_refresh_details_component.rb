# Appends feed-refresh specifics to the shared event detail list: how many
# posts the refresh imported and how long it took. Both come from the event's
# recorded stats and are skipped when missing.
class FeedRefreshDetailsComponent < EventDetailsComponent
  private

  def extra_items(component)
    add_new_posts_item(component)
    add_duration_item(component)
  end

  def add_new_posts_item(component)
    return if new_posts.blank?

    component.with_item(ListComponent::StatItemComponent.new(
      label: "New posts",
      value: new_posts,
      key: "events.new_posts"
    ))
  end

  def add_duration_item(component)
    return if total_duration.blank?

    component.with_item(ListComponent::StatItemComponent.new(
      label: "Duration",
      value: format_duration(total_duration),
      key: "events.duration"
    ))
  end

  # Refreshes usually finish in seconds, so a coarse "less than a minute" reads
  # as a non-answer. Show precise seconds, rolling up to minutes when it runs long.
  def format_duration(seconds)
    return "#{seconds.round(1)}s" if seconds < 60

    minutes = (seconds / 60).floor
    remaining = (seconds % 60).round

    "#{minutes}m #{remaining}s"
  end

  def stats
    (@event.metadata || {}).fetch("stats", {})
  end

  def new_posts
    stats["new_posts"]
  end

  def total_duration
    stats["total_duration"]
  end
end
