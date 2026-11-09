class WithdrawAllPostsJob < ApplicationJob
  include SetsFeedErrorContext

  queue_as :default

  # Queue tables share the application database: enqueue and disabling the feed
  # must commit together, while the feed row still serializes purge requests.
  self.enqueue_after_transaction_commit = false

  # Failed jobs retain a nil finished_at, but no longer count as purging.
  def self.in_progress_for?(feed_id)
    SolidQueue::Job.where(class_name: name, finished_at: nil)
      .where.missing(:failed_execution)
      .where("arguments::jsonb -> 'arguments' ->> 0 = ?", feed_id.to_s)
      .exists?
  end

  def perform(feed_id, user_id)
    feed = Feed.find_by(id: feed_id)
    return unless feed

    set_feed_error_context(feed)

    result = Feed::StateTransition.new(feed).disable
    raise ActiveRecord::RecordInvalid, feed unless result.success?

    user = User.find_by(id: user_id)
    return unless user

    access_token = feed.access_token
    return unless access_token&.active?

    WithdrawAllPosts.new(feed, user: user).call
  end
end
