# Recurring scheduler that drives publishing, decoupled from feed refresh.
#
# Refresh produces and persists posts on each feed's own cron; this job runs
# frequently and kicks a publish chain (PostPublishJob) for every enabled feed
# with unfinished publication work. It is also the chain's watchdog: a stalled
# or never-started chain is picked up on the next run, including for feeds that
# were disabled and re-enabled. Feeds with a live chain are skipped, so it only
# (re)starts idle ones rather than piling duplicate kicks onto a running chain.
class PublicationSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    Feed.enabled.where(id: feeds_with_unfinished_posts).find_each do |feed|
      # A held lock means a live chain is already publishing this feed and will
      # pick up the remaining posts. Kicking it would just enqueue a job that
      # fails to acquire the lock and skips, so only (re)start idle chains.
      next if Feed.advisory_lock_exists?("post_publish_#{feed.id}")

      PostPublishJob.perform_later(feed.id)
    end
  end

  private

  def feeds_with_unfinished_posts
    Post.where(status: :enqueued)
        .or(Post.where(id: PostPublication.select(:post_id)))
        .select(:feed_id)
        .distinct
  end
end
