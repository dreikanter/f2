class FeedSchedule < ApplicationRecord
  belongs_to :feed

  validates :feed_id, uniqueness: true

  def calculate_next_run_at
    Fugit.parse(feed.cron_expression).next_time.to_t
  end
end
