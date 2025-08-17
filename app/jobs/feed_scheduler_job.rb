class FeedSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    Feed.due.find_each do |feed|
      schedule = feed.feed_schedule

      if schedule
        updated = FeedSchedule
          .where(id: schedule.id, next_run_at: schedule.next_run_at)
          .update_all(next_run_at: schedule.calculate_next_run_at, last_run_at: Time.current)

        if updated == 1
          FeedRefreshJob.perform_later(feed.id)
        end
      else
        # Create initial schedule and queue job
        FeedSchedule.create!(
          feed: feed,
          next_run_at: Time.current,
          last_run_at: Time.current
        )
        FeedRefreshJob.perform_later(feed.id)
      end
    end
  end
end
