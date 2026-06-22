class FeedStatsComponent < ViewComponent::Base
  def initialize(feed:)
    @feed = feed
  end

  def call
    tag.div { safe_join([mobile_layout, desktop_layout]) }
  end

  private

  def mobile_layout
    render(DescriptionListComponent.new(css_class: class_names("md:hidden", DescriptionListComponent::DEFAULT_CSS_CLASSES))) do |list|
      layout_items.each { |item| list.with_item(mobile_stat_cell(item)) }
    end
  end

  def desktop_layout
    render(StatsBarComponent.new(css_class: class_names("hidden", StatsBarComponent::DEFAULT_CSS_CLASSES))) do |bar|
      layout_items.each { |item| bar.with_item(desktop_stat_cell(item)) }
    end
  end

  def layout_items
    @layout_items ||= [
      {
        key: "imported_posts",
        label: "Imported posts",
        label_short: "Imported",
        value: helpers.number_with_delimiter(imported_posts_count),
        muted: imported_posts_count.zero?
      },
      {
        key: "published_posts",
        label: "Published posts",
        label_short: "Published",
        value: helpers.number_with_delimiter(published_posts_count),
        muted: published_posts_count.zero?
      },
      {
        key: "posts_last_week",
        label: "Posts published last week",
        label_short: "Last week",
        value: helpers.number_with_delimiter(posts_last_week_count),
        muted: posts_last_week_count.zero?
      },
      {
        key: "last_refresh",
        label: "Last refresh",
        label_short: "Refreshed",
        value: last_refresh_value,
        muted: last_refreshed_at.nil?
      },
      {
        key: "most_recent_repost",
        label: "Most recent repost",
        label_short: "Recent",
        value: most_recent_repost_value,
        muted: most_recent_repost_at.nil?
      }
    ]
  end

  def mobile_stat_cell(item)
    ListComponent::StatItemComponent.new(
      label: item[:label],
      value: item[:value],
      key: "stats.#{item[:key]}",
      muted: item[:muted]
    )
  end

  def desktop_stat_cell(item)
    StatsBarComponent::StatItemComponent.new(
      label: item[:label_short],
      value: item[:value],
      key: "stats.#{item[:key]}",
      muted: item[:muted]
    )
  end

  def last_refresh_value
    last_refreshed_at ? helpers.short_time_ago_tag(last_refreshed_at) : "Never"
  end

  def most_recent_repost_value
    most_recent_repost_at ? helpers.short_time_ago_tag(most_recent_repost_at) : "–"
  end

  def last_refreshed_at
    return @last_refreshed_at if defined?(@last_refreshed_at)

    @last_refreshed_at = @feed.last_refreshed_at
  end

  def most_recent_repost_at
    return @most_recent_repost_at if defined?(@most_recent_repost_at)

    @most_recent_repost_at = @feed.most_recent_repost_at
  end

  def imported_posts_count
    @imported_posts_count ||= @feed.posts.count
  end

  def published_posts_count
    @published_posts_count ||= @feed.posts.published.count
  end

  def posts_last_week_count
    @posts_last_week_count ||= @feed.posts_published_last_week_count
  end
end
