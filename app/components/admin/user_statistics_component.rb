class Admin::UserStatisticsComponent < ViewComponent::Base
  def initialize(stats:)
    @stats = stats
  end

  def call
    render(DescriptionListComponent.new) do |list|
      list.with_item(ListComponent::StatItemComponent.new(label: "Feeds", value: feeds_value, key: "stats.feeds"))
      list.with_item(ListComponent::StatItemComponent.new(label: "Access Tokens", value: tokens_value, key: "stats.access_tokens"))
      list.with_item(ListComponent::StatItemComponent.new(label: "Posts", value: @stats.posts_count))
      list.with_item(ListComponent::StatItemComponent.new(label: "Most Recent Post", value: most_recent_post_value))
    end
  end

  private

  def feeds_value
    parts = ["#{@stats.feeds_count} total"]
    parts << "#{@stats.feeds_enabled_count} enabled" if @stats.feeds_enabled_count > 0
    parts << "#{@stats.feeds_disabled_count} disabled" if @stats.feeds_disabled_count > 0
    summarize(parts)
  end

  def tokens_value
    parts = ["#{@stats.access_tokens_count} total"]
    parts << "#{@stats.active_access_tokens_count} active" if @stats.active_access_tokens_count > 0
    parts << "#{@stats.inactive_access_tokens_count} not active" if @stats.inactive_access_tokens_count > 0
    summarize(parts)
  end

  def summarize(parts)
    parts.size > 1 ? "#{parts.first} (#{parts[1..].join(', ')})" : parts.first
  end

  def most_recent_post_value
    post = @stats.most_recent_post
    return helpers.tag.span("No posts yet", class: "text-slate-500") unless post

    time = post.published_at
    helpers.tag.time(
      "#{time.to_date.to_fs(:long)} (#{helpers.short_time_ago(time)})",
      datetime: time.iso8601,
      title: time.to_fs(:long)
    )
  end
end
