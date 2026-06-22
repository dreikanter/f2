class WithdrawAllPosts
  def initialize(feed)
    @feed = feed
    @client = feed.access_token.build_client
    @rate_limit_subject = feed.access_token.rate_limit_subject
  end

  def call
    affected_dates = Set.new

    @feed.posts.published.find_each do |post|
      withdraw(post, affected_dates)
    end

    affected_dates.each { |date| FeedMetric.recompute_published(feed: @feed, date: date) }
  end

  private

  def withdraw(post, affected_dates)
    loop do
      wait_for_capacity

      case attempt_delete(post)
      when :ok, :not_found
        affected_dates << post.reposted_at.to_date if post.reposted_at
        post.update!(freefeed_post_id: nil, status: :withdrawn)
        break
      when :error
        break
      end
      # :throttled — loop back and re-acquire capacity before retrying
    end
  end

  def wait_for_capacity
    loop do
      result = RateLimit.acquire(:freefeed, subject: @rate_limit_subject, cost: { delete: 1 })
      break if result.allowed?
      sleep(result.retry_after)
    end
  end

  def attempt_delete(post)
    @client.delete_post(post.freefeed_post_id)
    :ok
  rescue RateLimit::Throttled => e
    sleep(e.retry_after)
    :throttled
  rescue FreefeedClient::NotFoundError
    Rails.logger.warn("FreeFeed post #{post.freefeed_post_id} not found; syncing local record")
    :not_found
  rescue FreefeedClient::Error => e
    Rails.logger.error("Failed to withdraw post #{post.id} from FreeFeed: #{e.message}")
    :error
  end
end
