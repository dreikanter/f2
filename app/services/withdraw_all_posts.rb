class WithdrawAllPosts
  def initialize(feed, user:)
    @feed = feed
    @user = user
    @client = feed.access_token.build_client
    @rate_limit_subject = feed.access_token.rate_limit_subject
  end

  def call
    event = create_event
    started_at = Time.current
    affected_dates = Set.new
    deleted_count = 0

    @feed.posts.published.order(reposted_at: :asc).each do |post|
      deleted_count += 1 if withdraw(post, affected_dates)
    end

    affected_dates.each { |date| FeedMetric.recompute_published(feed: @feed, date: date) }
    finalize_event(event, started_at: started_at, deleted_count: deleted_count,
                   dates_from: affected_dates.min, dates_to: affected_dates.max)
  end

  private

  def create_event
    Event.create!(
      type: "group_purge_started",
      user: @user,
      subject: @feed,
      level: :info,
      metadata: { target_group: @feed.target_group }
    )
  end

  def finalize_event(event, started_at:, deleted_count:, dates_from:, dates_to:)
    stats = {
      "deleted_count" => deleted_count,
      "duration_seconds" => (Time.current - started_at).round(1)
    }
    if dates_from
      stats["dates_from"] = dates_from.iso8601
      stats["dates_to"] = dates_to.iso8601
    end
    event.update!(metadata: event.metadata.merge(stats))
  end

  def withdraw(post, affected_dates)
    loop do
      wait_for_capacity

      case attempt_delete(post)
      when :ok, :not_found
        affected_dates << post.reposted_at.to_date if post.reposted_at
        post.update!(freefeed_post_id: nil, status: :withdrawn)
        return true
      when :error
        return false
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
