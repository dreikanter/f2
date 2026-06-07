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
    reserve(feed, post)
    FreefeedPublisher.new(post).publish
    schedule_next(feed)
  rescue RateLimit::Throttled
    # No capacity: reschedule the whole job (RateLimited) for the same post.
    # Must precede the generic rescue so it isn't recorded as a failure.
    raise
  rescue FreefeedClient::UnauthorizedError
    # Token is no longer valid: disable it and stop the chain.
    feed.access_token&.disable_token_and_feeds
  rescue => e
    # Poison post: mark it failed and move on so the queue isn't blocked.
    post.update!(status: :failed)
    Rails.logger.error "Failed to publish post #{post.id}: #{e.message}"
    Rails.error.report(e, context: { post: post.attributes, feed: feed.attributes })
    schedule_next(feed)
  end

  # Reserve every POST the publish will make (the post, each comment, and each
  # attachment upload) against the FreeFeed POST bucket, up front and atomically.
  def reserve(feed, post)
    posts = 1 + post.comments.to_a.count(&:present?) + post.attachment_urls.to_a.size
    RateLimit.acquire!(:freefeed, subject: feed.access_token.rate_limit_subject, cost: { post: posts })
  end

  def schedule_next(feed)
    self.class.perform_later(feed.id)
  end
end
