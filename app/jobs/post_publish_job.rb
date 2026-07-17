# Publishes enqueued posts to FreeFeed one at a time, in order.
#
# It works as a self-chaining FIFO queue: each run publishes the earliest
# unfinished post for the feed, then schedules itself again for the next one. A
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
    post = feed.posts.where.not(next_comment_index: nil).order(:published_at, :id).first
    post ||= feed.posts.enqueued.order(:published_at, :id).first
    return unless post

    publish(feed, post)
  end

  def publish(feed, post)
    was_published = post.published?
    posts = post_cost(post)
    return reject_oversized(feed, post, posts) unless within_capacity?(posts)

    result = RateLimit.acquire(:freefeed, subject: feed.access_token.rate_limit_subject, cost: { post: posts })
    return reschedule_for_rate_limit(result.retry_after) unless result.allowed?

    publisher = FreefeedPublisher.new(post)
    post.next_comment_index.nil? ? publisher.publish : publisher.publish_pending_comments
    count_published(post) unless was_published
    schedule_next(feed)
  rescue RateLimit::Throttled => e
    # Leave any partial comment cursor intact and retry this feed after the
    # provider's cooldown. Newer posts remain behind the interrupted one.
    count_published(post) unless was_published
    reschedule_for_rate_limit(e.retry_after)
  rescue FreefeedClient::UnauthorizedError
    # Token is no longer valid: disable it and stop the chain.
    feed.access_token&.disable_token_and_feeds
  rescue FreefeedPublisher::TargetGroupUnavailableError => e
    # The target group is gone or no longer accepts our posts. The token is fine,
    # so disable just this feed (with an explanation) and stop the chain; the post
    # stays enqueued and resumes if the user fixes the target and re-enables.
    feed.disable_due_to_unavailable_target!(reason: e.reason, details: e.server_message)
  rescue FreefeedPublisher::CommentPublishError => e
    count_published(post) unless was_published
    record_comment_failure(feed, post, e)
  rescue FreefeedPublisher::SourceContentError => e
    # Source content is gone (e.g. an attachment 404s). Expected external
    # condition: fail the post and move on, but don't page error tracking.
    fail_post(feed, post, e)
  rescue => e
    # Poison post: mark it failed and move on so the queue isn't blocked.
    fail_post(feed, post, e, report: true)
  end

  # The post exists remotely, so comment delivery failure must not rewrite its
  # publication state. Record a user-visible error and continue with the queue.
  def record_comment_failure(feed, post, error)
    post.update_column(:next_comment_index, nil)
    Event.create!(
      type: "feed_post_comments_failed",
      level: :error,
      subject: feed,
      user: feed.user,
      message: error.message,
      metadata: { post_id: post.id, freefeed_post_id: post.freefeed_post_id }
    )
    Rails.logger.error "Failed to publish comments for post #{post.id}: #{error.message}"
    Rails.error.report(error, context: { post: post.attributes, feed: feed.attributes })
    schedule_next(feed)
  end

  # Mark a post failed and advance the chain. Reports to error tracking only for
  # unexpected faults; expected external failures are logged and skipped.
  def fail_post(feed, post, error, report: false)
    post.update!(status: :failed)
    Metrics.increment("posts_published_total", status: "failed")
    Rails.logger.error "Failed to publish post #{post.id}: #{error.message}"
    Rails.error.report(error, context: { post: post.attributes, feed: feed.attributes }) if report
    schedule_next(feed)
  end

  # Every POST still required for this publication. A post whose remote copy
  # already exists reserves capacity only for its remaining comments.
  def post_cost(post)
    if post.next_comment_index
      post.comments.drop(post.next_comment_index).count(&:present?)
    else
      1 + post.comments.count(&:present?) + post.attachment_urls.size
    end
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

  def count_published(post)
    return unless post.published?

    Metrics.increment("posts_published_total", status: "published")
    FeedMetric.recompute_published(feed: post.feed, date: post.reposted_at.to_date)
  end

  def schedule_next(feed)
    self.class.perform_later(feed.id)
  end
end
