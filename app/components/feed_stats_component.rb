class FeedStatsComponent < ViewComponent::Base
  def initialize(feed:)
    @feed = feed
  end

  def call
    tag.div { safe_join([mobile_layout, desktop_layout]) }
  end

  private

  def mobile_layout
    render(mobile_list_component)
  end

  def desktop_layout
    render(desktop_bar_component)
  end

  def layout_items
    @layout_items ||= [
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
        value: helpers.number_with_delimiter(imported_posts_count)
      },
      {
        key: "published_posts",
        label: "Published posts",
        label_short: "Published",
        value: helpers.number_with_delimiter(published_posts_count)
      }
    ]
  end

  def mobile_list_component
    ListGroupComponent.new(css_class: class_names("md:hidden", ListGroupComponent::DEFAULT_CSS_CLASSES)).tap do |list|
      layout_items.each { |item| list.with_item(mobile_stat_cell(item)) }
    end
  end

  def desktop_bar_component
    StatsBarComponent.new(css_class: class_names("hidden", StatsBarComponent::DEFAULT_CSS_CLASSES)).tap do |bar|
      layout_items.each { |item| bar.with_item(desktop_stat_cell(item)) }
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

  def imported_posts_count
    @imported_posts_count ||= @feed.posts.count
  end

  def published_posts_count
    @published_posts_count ||= @feed.posts.published.count
  end
end
