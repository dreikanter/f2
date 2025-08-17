class FeedSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    Feed.due.find_each do |feed|
      next unless schedule_feed_refresh?(feed)
      FeedRefreshJob.perform_later(feed.id)
    end
  end

  private

  def schedule_feed_refresh?(feed)
    schedule = feed.feed_schedule

    if schedule
      updated_records_count = update_existing_schedule(schedule)
      updated_records_count == 1
    else
      create_initial_schedule(feed)
      true
    end
  end

  def update_existing_schedule(schedule)
    FeedSchedule
      .where(id: schedule.id, next_run_at: schedule.next_run_at)
      .update_all(
        next_run_at: schedule.calculate_next_run_at,
        last_run_at: current_time
      )
  end

  def create_initial_schedule(feed)
    FeedSchedule.create!(
      feed: feed,
      next_run_at: current_time,
      last_run_at: current_time
    )
  end

  def current_time
    @current_time ||= Time.current
  end
end
