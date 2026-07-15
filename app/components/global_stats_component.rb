class GlobalStatsComponent < ViewComponent::Base
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
        value: most_recent_repost_at.present? ? helpers.short_time_ago(most_recent_repost_at) : "—"
      }
    ]
  end

  def mobile_stat_cell(item)
    StatListItemComponent.new(label: item[:label], value: item[:value], key: "stats.#{item[:key]}")
  end

  def desktop_stat_cell(item)
    StatBarItemComponent.new(label: item[:label_short], value: item[:value], key: "stats.#{item[:key]}")
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
