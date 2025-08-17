class Feed < ApplicationRecord
  has_one :feed_schedule, dependent: :destroy

  enum :state, { enabled: 0, paused: 1, disabled: 2 }

  validates :name, presence: true
  validates :url, presence: true
  validates :cron_expression, presence: true
  validates :loader, presence: true
  validates :processor, presence: true
  validates :normalizer, presence: true

  scope :due, -> {
    left_joins(:feed_schedule)
      .where("feed_schedules.next_run_at <= ? OR feed_schedules.id IS NULL", Time.current)
  }
end
