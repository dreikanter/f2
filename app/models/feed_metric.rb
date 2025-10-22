class FeedMetric < ApplicationRecord
  belongs_to :feed

  validates :date, presence: true
  validates :date, uniqueness: { scope: :feed_id }
  validates :posts_count, :invalid_posts_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :for_date_range, ->(start_date, end_date) {
    where(date: start_date..end_date)
  }

  scope :for_user, ->(user) {
    joins(:feed).where(feeds: { user_id: user.id })
  }

  # Record metrics for a specific date (upsert)
  # Only creates a record if there's actual activity (sparse data)
  # @param feed [Feed] the feed to record metrics for
  # @param date [Date] the date to record metrics for
  # @param posts_count [Integer] number of posts imported
  # @param invalid_posts_count [Integer] number of invalid posts
  def self.record(feed:, date:, posts_count: 0, invalid_posts_count: 0)
    # Only record if there's actual activity
    return if posts_count.zero? && invalid_posts_count.zero?

    upsert(
      {
        feed_id: feed.id,
        date: date,
        posts_count: posts_count,
        invalid_posts_count: invalid_posts_count
      },
      unique_by: [:feed_id, :date]
    )
  end
end
