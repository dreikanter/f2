class PostWithdrawalJob < ApplicationJob
  include RateLimited

  queue_as :default

  def perform(feed_id, freefeed_post_id, post_id = nil)
    return if freefeed_post_id.blank?

    feed = Feed.find_by(id: feed_id)
    return unless feed

    access_token = feed.access_token
    return unless access_token&.active?

    result = RateLimit.acquire(:freefeed, subject: access_token.rate_limit_subject, cost: { delete: 1 })
    return reschedule_for_rate_limit(result.retry_after) unless result.allowed?

    client = access_token.build_client
    client.delete_post(freefeed_post_id)

    Post.where(id: post_id).update_all(freefeed_post_id: nil)
  rescue RateLimit::Throttled => e
    reschedule_for_rate_limit(e.retry_after)
  rescue FreefeedClient::Error => e
    Rails.logger.error("Failed to withdraw FreeFeed post #{freefeed_post_id}: #{e.message}")
  end
end
