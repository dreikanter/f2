class FeedSchedule < ApplicationRecord
  belongs_to :feed

  def calculate_next_run_at
    Fugit.parse(feed.cron_expression).next_at.to_t
  end
end