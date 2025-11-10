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
      render(mobile_list_component)
    end
  end

  def desktop_layout
    tag.div class: "hidden md:flex md:divide-x md:divide-slate-200" do
      safe_join(layout_items(concise: true).map { |item| desktop_stat_cell(item) })
    end
  end

  def layout_items(concise: false)
    items = [
      { key: "total_feeds", label: concise ? "Feeds" : "Total feeds", value: number_with_delimiter(total_feeds_count) }
    ]

    if total_imported_posts_count.to_i.positive?
      items << { key: "total_imported_posts", label: concise ? "Imported" : "Total imported posts", value: number_with_delimiter(total_imported_posts_count) }
      items << { key: "total_published_posts", label: concise ? "Published" : "Total published posts", value: number_with_delimiter(total_published_posts_count) }

      if average_posts_per_day_last_week.present?
        items << { key: "average_posts_per_day", label: concise ? "Daily" : "Average posts per day (last week)", value: number_with_precision(average_posts_per_day_last_week.to_f, precision: 1) }
      end
    end

    if most_recent_post_published_at.present?
      items << { key: "most_recent_post_publication", label: concise ? "Recent" : "Most recent post publication", value: "#{time_ago_in_words(most_recent_post_published_at)} ago" }
    end

    items
  end

  def mobile_list_component
    ListGroupComponent.new.tap do |list|
      layout_items(concise: false).each do |item|
        list.with_item(mobile_stat_cell(item))
      end
    end
  end

  def mobile_stat_cell(item)
    ListGroupComponent::StatItemComponent.new(label: item[:label], value: item[:value], key: "stats.#{item[:key]}")
  end

  def desktop_stat_cell(item)
    tag.div class: "flex-1 flex flex-col items-center justify-center p-4 min-w-0", data: { key: "stats.#{item[:key]}" } do
      safe_join([
        tag.div(item[:value], class: "text-3xl font-semibold text-slate-900 whitespace-nowrap", data: { key: "stats.#{item[:key]}.value" }),
        tag.div(item[:label], class: "text-sm text-slate-600 whitespace-nowrap mt-1", data: { key: "stats.#{item[:key]}.label" })
      ])
    end
  end
end
