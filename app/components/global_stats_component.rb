class GlobalStatsComponent < StatsPanelComponent
  private

  def layout_items
    @layout_items ||= [
      {
        key: "total_users",
        label: "Total users",
        label_short: "Users",
        value: number_with_delimiter(total_users_count)
      },
      {
        key: "total_feeds",
        label: "Total feeds",
        label_short: "Feeds",
        value: number_with_delimiter(total_feeds_count)
      },
      {
        key: "total_imported_posts",
        label: "Total imported posts",
        label_short: "Imported",
        value: number_with_delimiter(total_imported_posts_count)
      },
      {
        key: "total_published_posts",
        label: "Total published posts",
        label_short: "Published",
        value: number_with_delimiter(total_published_posts_count)
      },
      {
        key: "posts_last_week",
        label: "Posts published last week",
        label_short: "Last week",
        value: number_with_delimiter(posts_published_last_week_count)
      },
      {
        key: "most_recent_repost",
        label: "Most recent repost",
        label_short: "Recent",
        value: (helpers.short_time_ago(most_recent_repost_at) if most_recent_repost_at)
      }
    ]
  end

  def total_users_count
    User.count
  end

  def total_feeds_count
    Feed.count
  end

  def total_imported_posts_count
    Post.count
  end

  def total_published_posts_count
    Post.published.count
  end

  def posts_published_last_week_count
    Post.where(published_at: 1.week.ago.beginning_of_day..Time.current.end_of_day).count
  end

  def most_recent_repost_at
    @most_recent_repost_at ||= Post.published.maximum(:reposted_at)
  end
end
