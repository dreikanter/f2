class PostWithdrawalJob < ApplicationJob
  queue_as :default

  def perform(feed_id, freefeed_post_id)
    return if freefeed_post_id.blank?

    feed = Feed.find_by(id: feed_id)
    return unless feed

    access_token = feed.access_token
    return unless access_token&.active?

    client = access_token.build_client
    client.delete_post(freefeed_post_id)
  rescue FreefeedClient::Error => e
    Rails.logger.error("Failed to withdraw FreeFeed post #{freefeed_post_id}: #{e.message}")
  end
end
