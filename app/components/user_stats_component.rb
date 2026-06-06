class UserStatsComponent < ViewComponent::Base
  def initialize(user:)
    @user = user
  end

  def call
    tag.div { safe_join([mobile_layout, desktop_layout]) }
  end

  private

  attr_reader :user

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
        value: user.most_recent_repost_at.present? ? "#{helpers.short_time_ago(user.most_recent_repost_at)} ago" : "—"
      }
    ]
  end

  def mobile_stat_cell(item)
    ListComponent::StatItemComponent.new(label: item[:label], value: item[:value], key: "stats.#{item[:key]}")
  end

  def desktop_stat_cell(item)
    StatsBarComponent::StatItemComponent.new(label: item[:label_short], value: item[:value], key: "stats.#{item[:key]}")
  end
end
