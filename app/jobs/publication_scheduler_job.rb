# Recurring scheduler that drives publishing, decoupled from feed refresh.
#
# Refresh produces and persists posts on each feed's own cron; this job runs
# frequently and kicks a publish chain (PostPublishJob) for every enabled feed
# that has enqueued posts waiting. It is also the chain's watchdog: a stalled or
# never-started chain is picked up on the next run, including for feeds that were
# disabled and re-enabled.
class PublicationSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    Feed.enabled.where(id: feeds_with_enqueued_posts).find_each do |feed|
      PostPublishJob.perform_later(feed.id)
    end
  end

  private

  def feeds_with_enqueued_posts
    Post.enqueued.select(:feed_id).distinct
  end
end
