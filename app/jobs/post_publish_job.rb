# Publishes enqueued posts to FreeFeed one at a time, in order.
#
# It works as a self-chaining FIFO queue: each run publishes the earliest
# enqueued post for the feed, then schedules itself again for the next one. A
# per-feed advisory lock guarantees a single active chain, so posts keep their
# original order and are never published concurrently.
#
# The chain is self-healing: if a run dies before scheduling the next one, the
# feed's next refresh kicks it off again and it resumes from the earliest
# remaining post.
class PostPublishJob < ApplicationJob
  queue_as :default

  def perform(feed_id)
    feed = Feed.find_by(id: feed_id)
    return unless feed

    Feed.with_advisory_lock("post_publish_#{feed_id}", timeout_seconds: 0) do
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
    FreefeedPublisher.new(post).publish
    schedule_next(feed)
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

  def schedule_next(feed)
    self.class.perform_later(feed.id)
  end
end
