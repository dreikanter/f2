module FeedHelper
  def feed_missing_enablement_parts(feed)
    missing_parts = []
    missing_parts << "active access token" unless feed.access_token&.active?
    missing_parts << "target group" unless feed.target_group.present?
    missing_parts
  end
end
