class StatusStatsComponent < ViewComponent::Base
  def initialize(
    total_feeds_count:,
    total_imported_posts_count: 0,
    total_published_posts_count: 0,
    most_recent_post_published_at: nil,
    average_posts_per_day_last_week: nil
  )
    @total_feeds_count = total_feeds_count
    @total_imported_posts_count = total_imported_posts_count
    @total_published_posts_count = total_published_posts_count
    @most_recent_post_published_at = most_recent_post_published_at
    @average_posts_per_day_last_week = average_posts_per_day_last_week
  end

  def call
    render(list_component)
  end

  private

  attr_reader :total_feeds_count,
              :total_imported_posts_count,
              :total_published_posts_count,
              :most_recent_post_published_at,
              :average_posts_per_day_last_week

  def list_component
    ListGroupComponent.new.tap do |list|
      list.with_item(stat_item("total_feeds", "Total feeds", number_with_delimiter(total_feeds_count)))

      if total_imported_posts_count.to_i.positive?
        list.with_item(stat_item("total_imported_posts", "Total imported posts", number_with_delimiter(total_imported_posts_count)))
        list.with_item(stat_item("total_published_posts", "Total published posts", number_with_delimiter(total_published_posts_count)))

        if average_posts_per_day_last_week.present?
          list.with_item(stat_item("average_posts_per_day", "Average posts per day (last week)", number_with_precision(average_posts_per_day_last_week.to_f, precision: 1)))
        end
      end

      if most_recent_post_published_at.present?
        list.with_item(stat_item("most_recent_post_publication", "Most recent post publication", "#{time_ago_in_words(most_recent_post_published_at)} ago"))
      end
    end
  end

  def stat_item(key_suffix, label, value)
    ListGroupComponent::StatItemComponent.new(label: label, value: value, key: "stats.#{key_suffix}")
  end
end
