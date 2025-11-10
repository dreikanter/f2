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
    render(mobile_list_component)
  end

  def desktop_layout
    render(desktop_bar_component)
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
        key: "average_posts_per_day",
        label: "Average posts per day (last week)",
        label_short: "Daily",
        value: user.average_posts_per_day_last_week.present? ? number_with_precision(user.average_posts_per_day_last_week.to_f, precision: 1) : "—"
      },
      {
        key: "most_recent_post_publication",
        label: "Most recent post publication",
        label_short: "Recent",
        value: user.most_recent_post_published_at.present? ? "#{time_ago_in_words(user.most_recent_post_published_at)} ago" : "—"
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
    ListGroupComponent::StatItemComponent.new(label: item[:label], value: item[:value], key: "stats.#{item[:key]}")
  end

  def desktop_stat_cell(item)
    StatsBarComponent::StatItemComponent.new(label: item[:label_short], value: item[:value], key: "stats.#{item[:key]}")
  end
end
