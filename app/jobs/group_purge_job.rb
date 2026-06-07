class GroupPurgeJob < ApplicationJob
  include RateLimited

  queue_as :default

  def perform(feed_id)
    feed = Feed.find_by(id: feed_id)
    return unless feed

    access_token = feed.access_token
    return unless access_token&.active?

    client = access_token.build_client

    # Posts cleared below drop out of this scope, so a rescheduled run (on throttle)
    # resumes with whatever is left rather than re-deleting.
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
  end
end
