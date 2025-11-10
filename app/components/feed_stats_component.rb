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
    render(mobile_list_component)
  end

  def desktop_layout
    tag.div class: "hidden md:flex md:divide-x md:divide-slate-200" do
      safe_join(desktop_layout_items.map { |item| desktop_stat_cell(item) })
    end
  end

  def mobile_layout_items
    [
      {
        key: "last_refresh",
        label: "Last refresh",
        value: last_refresh_value
      },
      {
        key: "most_recent_post",
        label: "Most recent publication",
        value: most_recent_post_value
      },
      {
        key: "imported_posts",
        label: "Imported posts",
        value: helpers.number_with_delimiter(@feed.posts.count)
      },
      {
        key: "published_posts",
        label: "Published posts",
        value: helpers.number_with_delimiter(@feed.posts.published.count)
      }
    ]
  end

  def desktop_layout_items
    [
      {
        key: "last_refresh",
        label: "Refreshed",
        value: last_refresh_value
      },
      {
        key: "most_recent_post",
        label: "Recent",
        value: most_recent_post_value
      },
      {
        key: "imported_posts",
        label: "Imported",
        value: helpers.number_with_delimiter(@feed.posts.count)
      },
      {
        key: "published_posts",
        label: "Published",
        value: helpers.number_with_delimiter(@feed.posts.published.count)
      }
    ]
  end

  def mobile_list_component
    ListGroupComponent.new(css_class: "md:hidden divide-y divide-slate-200").tap do |list|
      mobile_layout_items.each do |item|
        list.with_item(mobile_stat_cell(item))
      end
    end
  end

  def mobile_stat_cell(item)
    ListGroupComponent::StatItemComponent.new(
      label: item[:label],
      value: item[:value],
      key: "stats.#{item[:key]}"
    )
  end

  def desktop_stat_cell(item)
    tag.div class: "flex-1 flex flex-col items-center justify-center p-4 min-w-0", data: { key: "stats.#{item[:key]}" } do
      safe_join([
        tag.div(item[:value], class: "text-3xl font-semibold text-slate-900 whitespace-nowrap", data: { key: "stats.#{item[:key]}.value" }),
        tag.div(item[:label], class: "text-sm text-slate-600 whitespace-nowrap mt-1", data: { key: "stats.#{item[:key]}.label" })
      ])
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
