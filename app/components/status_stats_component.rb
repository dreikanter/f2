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
    tag.div class: "rounded-lg border border-slate-200 bg-white shadow-sm overflow-hidden" do
      safe_join([mobile_layout, desktop_layout])
    end
  end

  private

  attr_reader :total_feeds_count,
              :total_imported_posts_count,
              :total_published_posts_count,
              :most_recent_post_published_at,
              :average_posts_per_day_last_week

  def mobile_layout
    tag.div class: "md:hidden divide-y divide-slate-200" do
      render(list_component)
    end
  end

  def desktop_layout
    tag.div class: "hidden md:flex md:divide-x md:divide-slate-200" do
      safe_join(desktop_stats_items.map { |item| stat_cell(item) })
    end
  end

  def desktop_stats_items
    items = [
      { key: "total_feeds", label: "Feeds", value: number_with_delimiter(total_feeds_count) }
    ]

    if total_imported_posts_count.to_i.positive?
      items << { key: "total_imported_posts", label: "Imported", value: number_with_delimiter(total_imported_posts_count) }
      items << { key: "total_published_posts", label: "Published", value: number_with_delimiter(total_published_posts_count) }

      if average_posts_per_day_last_week.present?
        items << { key: "average_posts_per_day", label: "Daily", value: number_with_precision(average_posts_per_day_last_week.to_f, precision: 1) }
      end
    end

    if most_recent_post_published_at.present?
      items << { key: "most_recent_post_publication", label: "Recent", value: "#{time_ago_in_words(most_recent_post_published_at)} ago" }
    end

    items
  end

  def stat_cell(item)
    tag.div class: "flex-1 flex flex-col items-center justify-center p-4 min-w-0", data: { key: "stats.#{item[:key]}" } do
      safe_join([
        tag.div(item[:value], class: "text-3xl font-semibold text-slate-900 whitespace-nowrap", data: { key: "stats.#{item[:key]}.value" }),
        tag.div(item[:label], class: "text-sm text-slate-600 whitespace-nowrap mt-1", data: { key: "stats.#{item[:key]}.label" })
      ])
    end
  end

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
