class UserStatsComponent < StatsPanelComponent
  def initialize(user:)
    @user = user
  end

  private

  attr_reader :user

  def layout_items
    @layout_items ||= [
      {
        key: "total_feeds",
        label: "Total feeds",
        label_short: "Feeds",
        value: number_with_delimiter(user.total_feeds_count)
      },
      {
        key: "total_imported_posts",
        label: "Total imported posts",
        label_short: "Imported",
        value: number_with_delimiter(user.total_imported_posts_count)
      },
      {
        key: "total_published_posts",
        label: "Total published posts",
        label_short: "Published",
        value: number_with_delimiter(user.total_published_posts_count)
      },
      {
        key: "posts_last_week",
        label: "Posts published last week",
        label_short: "Last week",
        value: number_with_delimiter(user.posts_published_last_week_count)
      },
      {
        key: "most_recent_repost",
        label: "Most recent repost",
        label_short: "Recent",
        value: user.most_recent_repost_at.present? ? helpers.short_time_ago(user.most_recent_repost_at) : "—"
      }
    ]
  end
end
