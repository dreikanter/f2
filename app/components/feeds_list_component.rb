class FeedsListComponent < ViewComponent::Base
  def initialize(feeds:)
    @feeds = feeds
  end

  def call
    component = ListGroupComponent.new

    @feeds.each do |feed|
      component.with_item(ListGroupComponent::FeedItemComponent.new(
        icon: helpers.feed_status_icon(feed),
        title: feed.name,
        title_url: helpers.feed_path(feed),
        metadata_segments: metadata_segments_for(feed)
      ))
    end

    render(component)
  end

  private

  def metadata_segments_for(feed)
    [
      "Target: #{feed.target_group.presence || 'None'}",
      safe_join(["Last refresh:", feed.last_refreshed_at ? helpers.short_time_ago_tag(feed.last_refreshed_at) : "Never"], " "),
      safe_join(["Recent post:", feed.most_recent_post_date ? helpers.short_time_ago_tag(feed.most_recent_post_date) : "None"], " ")
    ]
  end
end
