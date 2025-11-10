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
    render(desktop_bar_component)
  end

  def layout_items
    [
      {
        key: "last_refresh",
        label: "Last refresh",
        label_short: "Refreshed",
        value: last_refresh_value
      },
      {
        key: "most_recent_post",
        label: "Most recent publication",
        label_short: "Recent",
        value: most_recent_post_value
      },
      {
        key: "imported_posts",
        label: "Imported posts",
        label_short: "Imported",
        value: helpers.number_with_delimiter(@feed.posts.count)
      },
      {
        key: "published_posts",
        label: "Published posts",
        label_short: "Published",
        value: helpers.number_with_delimiter(@feed.posts.published.count)
      }
    ]
  end

  def mobile_list_component
    ListGroupComponent.new(css_class: "md:hidden divide-y divide-slate-200").tap do |list|
      layout_items.each do |item|
        list.with_item(mobile_stat_cell(item))
      end
    end
  end

  def desktop_bar_component
    StatsBarComponent.new.tap do |bar|
      layout_items.each do |item|
        bar.with_item(desktop_stat_cell(item))
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
    StatsBarComponent::StatItemComponent.new(
      label: item[:label_short],
      value: item[:value],
      key: "stats.#{item[:key]}"
    )
  end

  def last_refresh_value
    if @feed.last_refreshed_at
      helpers.short_time_ago_tag(@feed.last_refreshed_at)
    else
      content_tag(:span, "Never", class: "text-slate-500")
    end
  end

  def most_recent_post_value
    if @feed.most_recent_post_date
      helpers.short_time_ago_tag(@feed.most_recent_post_date)
    else
      content_tag(:span, "No posts imported", class: "text-slate-500")
    end
  end
end
