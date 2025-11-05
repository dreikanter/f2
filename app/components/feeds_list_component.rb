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
      target_segment(feed),
      safe_join(["Refreshed:", feed.last_refreshed_at ? content_tag(:span, "#{helpers.short_time_ago(feed.last_refreshed_at)} ago", title: helpers.long_time_format(feed.last_refreshed_at)) : "Never"], " "),
      safe_join(["Publication:", feed.most_recent_post_date ? content_tag(:span, "#{helpers.short_time_ago(feed.most_recent_post_date)} ago", title: helpers.long_time_format(feed.most_recent_post_date)) : "None"], " ")
    ]
  end

  def target_segment(feed)
    target = feed.target_group.presence || "None"
    return "Target: #{target}" if target == "None" || !feed.access_token

    url = "#{feed.access_token.host}/#{feed.target_group}"
    safe_join(["Target:", helpers.link_to(target, url, target: "_blank", rel: "noopener", class: "ff-link")], " ")
  end
end
