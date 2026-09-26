class FeedSchedule < ApplicationRecord
  belongs_to :feed

  validates :feed_id, uniqueness: true

  def calculate_next_run_at
    return next_interval_run_at if feed.refresh_interval.present?

    Fugit.parse(feed.cron_expression).next_time.to_t
  end

  private

  def next_interval_run_at
    interval = feed.refresh_interval
    return Time.current + rand(1..interval).seconds if next_run_at.nil?
    return next_run_at if next_run_at > Time.current

    steps = ((Time.current - next_run_at) / interval).floor + 1
    next_run_at + (steps * interval).seconds
  end
end
