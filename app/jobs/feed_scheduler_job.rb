class FeedSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    Feed.due.includes(:feed_schedule).find_each do |feed|
      FeedRefreshJob.perform_later(feed.id) if refresh?(feed)
    end
  end

  private

  def refresh?(feed)
    return false unless feed.scheduled?

    update_existing_schedule(feed.feed_schedule) == 1
  end

  def update_existing_schedule(schedule)
    FeedSchedule
      .where(id: schedule.id, next_run_at: schedule.next_run_at)
      .update_all(
        next_run_at: schedule.calculate_next_run_at,
        last_run_at: current_time
      )
  end

  def current_time
    @current_time ||= Time.current
  end
end
