module FeedHelper
  def feed_missing_enablement_parts(feed)
    missing_parts = []
    missing_parts << "URL" unless feed.url.present?
    missing_parts << "feed profile" unless feed.feed_profile_present?
    missing_parts << "active access token" unless feed.access_token&.active?
    missing_parts << "target group" unless feed.target_group.present?
    missing_parts << "schedule" unless feed.cron_expression.present?
    missing_parts
  end
end
