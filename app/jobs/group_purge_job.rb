class GroupPurgeJob < ApplicationJob
  queue_as :default

  def perform(feed_id)
    feed = Feed.find_by(id: feed_id)
    return unless feed

    access_token = feed.access_token
    return unless access_token&.active?

    client = access_token.build_client
    posts = feed.posts.where.not(freefeed_post_id: [nil, ""])

    posts.find_each do |post|
      loop do
        result = RateLimit.acquire(:freefeed, subject: access_token.rate_limit_subject, cost: { delete: 1 })
        unless result.allowed?
          sleep(result.retry_after)
          next
        end

        begin
          client.delete_post(post.freefeed_post_id)
          post.update!(freefeed_post_id: nil)
          break
        rescue RateLimit::Throttled => e
          sleep(e.retry_after)
        rescue FreefeedClient::Error => e
          Rails.logger.error("Failed to withdraw post #{post.id} from FreeFeed: #{e.message}")
          break
        end
      end
    end
  end
end
