# Publishes enqueued posts to FreeFeed one at a time, in order.
#
# It works as a self-chaining FIFO queue: each run publishes the earliest
# enqueued post for the feed, then schedules itself again for the next one. A
# per-feed advisory lock guarantees a single active chain, so posts keep their
# original order and are never published concurrently.
#
# The chain is self-healing: if a run dies before scheduling the next one, the
# recurring PublicationSchedulerJob (the primary watchdog, every minute) kicks it
# off again and it resumes from the earliest remaining post. It also recovers
# feeds that were disabled and later re-enabled.
class PostPublishJob < ApplicationJob
  include RateLimited

  queue_as :default

  def perform(feed_id)
    feed = Feed.find_by(id: feed_id)
    return unless feed

    # Stop the chain if the feed was disabled after it was kicked. Disabling a
    # feed pauses publishing, including posts already enqueued.
    return unless feed.enabled?

    Feed.with_advisory_lock!("post_publish_#{feed_id}", timeout_seconds: 0) do
      publish_next(feed)
    end
  rescue WithAdvisoryLock::FailedToAcquireLock
    # A chain is already running for this feed; it will pick up remaining posts.
    Rails.logger.info "Publish chain already running for feed #{feed_id}, skipping"
  end

  private

  def publish_next(feed)
    post = feed.posts.enqueued.order(:published_at, :id).first
    return unless post

    publish(feed, post)
  end

  def publish(feed, post)
    posts = post_cost(post)
    return reject_oversized(feed, post, posts) unless within_capacity?(posts)

    result = RateLimit.acquire(:freefeed, subject: feed.access_token.rate_limit_subject, cost: { post: posts })
    return reschedule_for_rate_limit(result.retry_after) unless result.allowed?

    FreefeedPublisher.new(post).publish
    count_published(post)
    schedule_next(feed)
  rescue RateLimit::Throttled => e
    # Defer the same post (the idempotency guard keeps the retry safe). Before
    # the generic rescue so a throttle isn't recorded as a failure. count_published
    # still fires if a comment throttle had already created the post.
    count_published(post)
    reschedule_for_rate_limit(e.retry_after)
  rescue FreefeedClient::UnauthorizedError
    # Token is no longer valid: disable it and stop the chain.
    feed.access_token&.disable_token_and_feeds
  rescue => e
    # Poison post: mark it failed and move on so the queue isn't blocked.
    post.update!(status: :failed)
    Metrics.increment("posts_published_total", status: "failed")
    Rails.logger.error "Failed to publish post #{post.id}: #{e.message}"
    Rails.error.report(e, context: { post: post.attributes, feed: feed.attributes })
    schedule_next(feed)
  end

  # Every POST the publish will make: the post, each comment, and each
  # attachment upload (all hit FreeFeed's POST bucket).
  def post_cost(post)
    1 + post.comments.to_a.count(&:present?) + post.attachment_urls.to_a.size
  end

  def within_capacity?(posts)
    capacity = RateLimit.capacity(:freefeed, :post)
    capacity.nil? || posts <= capacity
  end

  # A post needing more POSTs than the bucket can ever hold would throttle
  # forever and block the queue, so fail it and move on.
  def reject_oversized(feed, post, posts)
    post.update!(status: :failed)
    Metrics.increment("posts_published_total", status: "rejected")
    Rails.logger.error "Post #{post.id} needs #{posts} POSTs, over the FreeFeed limit; marking failed"
    schedule_next(feed)
  end

  # Count a post once it's actually on FreeFeed. Guarded on status: an upfront
  # throttle (post never created) doesn't count; a mid-comment one does.
  def count_published(post)
    Metrics.increment("posts_published_total", status: "published") if post.published?
  end

  def schedule_next(feed)
    self.class.perform_later(feed.id)
  end
end
