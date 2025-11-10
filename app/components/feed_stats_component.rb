class FeedStatsComponent < ViewComponent::Base
  def initialize(feed:)
    @feed = feed
  end

  def call
    tag.div class: "rounded-lg border border-slate-200 bg-white shadow-sm overflow-hidden" do
      safe_join([mobile_layout, desktop_layout])
    end
  end

  private

  def mobile_layout
    tag.div class: "md:hidden divide-y divide-slate-200" do
      render(list_component)
    end
  end

  def desktop_layout
    tag.div class: "hidden md:flex md:divide-x md:divide-slate-200" do
      safe_join(desktop_stats_items.map { |item| stat_cell(item) })
    end
  end

  def desktop_stats_items
    [
      { key: "last_refresh", label: "Refreshed", value: last_refresh_value },
      { key: "most_recent_post", label: "Recent", value: most_recent_post_value },
      { key: "imported_posts", label: "Imported", value: helpers.number_with_delimiter(@feed.posts.count) },
      { key: "published_posts", label: "Published", value: helpers.number_with_delimiter(@feed.posts.published.count) }
    ]
  end

  def stat_cell(item)
    tag.div class: "flex-1 flex flex-col items-center justify-center p-4 min-w-0", data: { key: "stats.#{item[:key]}" } do
      safe_join([
        tag.div(item[:value], class: "text-3xl font-semibold text-slate-900 whitespace-nowrap", data: { key: "stats.#{item[:key]}.value" }),
        tag.div(item[:label], class: "text-sm text-slate-600 whitespace-nowrap mt-1", data: { key: "stats.#{item[:key]}.label" })
      ])
    end
  end

  def list_component
    ListGroupComponent.new.tap do |component|
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
    end
  end

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
