class WithdrawAllPosts
  def initialize(feed, user:)
    @feed = feed
    @user = user
  end

  def call
    event = create_event
    started_at = Time.current
    affected_dates = Set.new

    deleted_count = published_posts.count do |post|
      withdraw(post, affected_dates:)
    end

    recompute_metrics(affected_dates)
    finalize_event(
      event,
      started_at:,
      deleted_count:,
      affected_dates:
    )
  end

  private

  attr_reader :feed, :user

  def published_posts
    feed.posts.published.order(reposted_at: :asc)
  end

  def client
    @client ||= feed.access_token.build_client
  end

  def rate_limit_subject
    @rate_limit_subject ||= feed.access_token.rate_limit_subject
  end

  def create_event
    Event.create!(
      type: "group_purge_started",
      user:,
      subject: feed,
      level: :info,
      metadata: {
        target_group: feed.target_group
      }
    )
  end

  def withdraw(post, affected_dates:)
    with_delete_capacity do
      delete_remote_post(post)
    end

    mark_withdrawn(post)
    affected_dates << post.reposted_at.to_date if post.reposted_at?

    true
  rescue FreefeedClient::NotFoundError
    Rails.logger.warn(
      "FreeFeed post #{post.freefeed_post_id} not found; syncing local record"
    )

    mark_withdrawn(post)
    affected_dates << post.reposted_at.to_date if post.reposted_at?

    true
  rescue FreefeedClient::Error => e
    Rails.logger.error(
      "Failed to withdraw post #{post.id} from FreeFeed: #{e.message}"
    )

    false
  end

  # Sleep rather than reschedule: purging is a one-shot operation;
  # sleeping holds one worker but avoids re-enqueuing with saved cursor state.
  def with_delete_capacity
    loop do
      wait_for_capacity

      yield
      return
    rescue RateLimit::Throttled => e
      sleep(e.retry_after)
    end
  end

  def wait_for_capacity
    loop do
      result = RateLimit.acquire(
        :freefeed,
        subject: rate_limit_subject,
        cost: { delete: 1 }
      )

      return if result.allowed?

      sleep(result.retry_after)
    end
  end

  def delete_remote_post(post)
    client.delete_post(post.freefeed_post_id)
  end

  def mark_withdrawn(post)
    post.update!(
      freefeed_post_id: nil,
      status: :withdrawn
    )
  end

  def recompute_metrics(dates)
    dates.each do |date|
      FeedMetric.recompute_published(feed:, date:)
    end
  end

  def finalize_event(event, started_at:, deleted_count:, affected_dates:)
    event.update!(
      metadata: event.metadata.merge(
        event_stats(
          started_at:,
          deleted_count:,
          affected_dates:
        )
      )
    )
  end

  def event_stats(started_at:, deleted_count:, affected_dates:)
    {
      "deleted_count" => deleted_count,
      "duration_seconds" => (Time.current - started_at).round(1)
    }.tap do |stats|
      next if affected_dates.empty?

      stats["dates_from"] = affected_dates.min.iso8601
      stats["dates_to"] = affected_dates.max.iso8601
    end
  end
end
