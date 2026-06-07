class GroupPurgeJob < ApplicationJob
  queue_as :default

  def perform(feed_id)
    feed = Feed.find_by(id: feed_id)
    return unless feed

    access_token = feed.access_token
    return unless access_token&.active?

    client = access_token.build_client

    # Posts cleared below drop out of this scope, so a rescheduled run resumes
    # with whatever is left.
    posts = feed.posts.where.not(freefeed_post_id: [nil, ""])

    posts.find_each do |post|
      RateLimit.acquire!(:freefeed, subject: access_token.rate_limit_subject, cost: { delete: 1 })

      begin
        client.delete_post(post.freefeed_post_id)
        post.update!(freefeed_post_id: nil)
      rescue FreefeedClient::Error => e
        Rails.logger.error("Failed to withdraw post #{post.id} from FreeFeed: #{e.message}")
        # Continue with next post even if one fails
      end
    end
  rescue RateLimit::Throttled => e
    # This is a batch job, so retrying the same job (the RateLimited pattern) would
    # count against the attempt cap and only nibble a few posts per run. Instead,
    # re-enqueue a fresh job for the remaining posts after the cooldown — already
    # cleared posts are skipped, and the batch shrinks until it drains.
    self.class.set(wait: e.retry_after).perform_later(feed_id)
  end
end
