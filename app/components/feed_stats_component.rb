class FeedStatsComponent < ViewComponent::Base
  def initialize(feed:)
    @feed = feed
  end

  def call
    component = ListGroupComponent.new

    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "Last refresh",
      value: last_refresh_value,
      key: "stats.last_refresh"
    ))

    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "Most recent publication",
      value: most_recent_post_value,
      key: "stats.most_recent_post"
    ))

    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "Imported posts",
      value: helpers.number_with_delimiter(@feed.posts.count),
      key: "stats.imported_posts"
    ))

    component.with_item(ListGroupComponent::StatItemComponent.new(
      label: "Published posts",
      value: helpers.number_with_delimiter(@feed.posts.published.count),
      key: "stats.published_posts"
    ))

    render(component)
  end

  private

  def last_refresh_value
    if @feed.last_refreshed_at
      helpers.datetime_with_duration_tag(@feed.last_refreshed_at)
    else
      content_tag(:span, "Never", class: "text-slate-500")
    end
  end

  def most_recent_post_value
    if @feed.most_recent_post_date
      helpers.datetime_with_duration_tag(@feed.most_recent_post_date)
    else
      content_tag(:span, "No posts imported", class: "text-slate-500")
    end
  end
end
