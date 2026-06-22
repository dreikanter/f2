class GroupPurgeJob < ApplicationJob
  queue_as :default

  def perform(feed_id)
    feed = Feed.find_by(id: feed_id)
    return unless feed

    access_token = feed.access_token
    return unless access_token&.active?

    client = access_token.build_client
    posts = feed.posts.published

    affected_dates = Set.new

    posts.find_each do |post|
      loop do
        result = RateLimit.acquire(:freefeed, subject: access_token.rate_limit_subject, cost: { delete: 1 })
        unless result.allowed?
          sleep(result.retry_after)
          next
        end

        begin
          client.delete_post(post.freefeed_post_id)
          affected_dates << post.reposted_at.to_date if post.reposted_at
          post.update!(freefeed_post_id: nil, status: :withdrawn)
          break
        rescue RateLimit::Throttled => e
          sleep(e.retry_after)
        rescue FreefeedClient::Error => e
          Rails.logger.error("Failed to withdraw post #{post.id} from FreeFeed: #{e.message}")
          break
        end
      end
    end

    affected_dates.each { |date| FeedMetric.recompute_published(feed: feed, date: date) }
  end
end
