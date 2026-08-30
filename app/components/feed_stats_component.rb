class FeedStatsComponent < StatsPanelComponent
  def initialize(feed:)
    @feed = feed
  end

  private

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
        label: "Posts published in the last 7 days",
        label_short: "Last 7 days",
        value: helpers.number_with_delimiter(posts_last_week_count),
        muted: posts_last_week_count.zero?
      },
      {
        key: "subscribers",
        label: "Subscribers",
        label_short: "Subscribers",
        value: subscribers_value,
        muted: @feed.subscribers_count.to_i.zero?
      },
      {
        key: "last_refresh",
        label: @feed.scheduled? ? "Last refresh" : "Last post received",
        label_short: @feed.scheduled? ? "Refreshed" : "Received",
        value: last_refresh_value
      },
      {
        key: "most_recent_repost",
        label: "Most recent repost",
        label_short: "Recent",
        value: most_recent_repost_value
      }
    ]
  end

  def subscribers_value
    helpers.number_with_delimiter(@feed.subscribers_count) if @feed.subscribers_count
  end

  def last_refresh_value
    helpers.short_time_ago_tag(last_refreshed_at) if last_refreshed_at
  end

  def most_recent_repost_value
    helpers.short_time_ago_tag(most_recent_repost_at) if most_recent_repost_at
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
    @feed.imported_posts_count
  end

  def published_posts_count
    @feed.published_posts_count
  end

  def posts_last_week_count
    @posts_last_week_count ||= @feed.posts_published_last_week_count
  end
end
