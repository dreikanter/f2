class FeedMetric < ApplicationRecord
  belongs_to :feed

  validates :date, presence: true
  validates :date, uniqueness: { scope: :feed_id }
  validates :posts_count, :invalid_posts_count, :published_posts_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :for_date_range, ->(start_date, end_date) {
    where(date: start_date..end_date)
  }

  scope :for_user, ->(user) {
    joins(:feed).where(feeds: { user_id: user.id })
  }

  # Keep daily import metrics sparse by recording days with activity.
  # @param feed [Feed] source feed
  # @param date [Date] activity date
  # @param posts_count [Integer] imported post count
  # @param invalid_posts_count [Integer] invalid post count
  def self.record(feed:, date:, posts_count: 0, invalid_posts_count: 0)
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

  # Recompute the published-post count for a feed/date straight from the posts.
  # Called after a post is published, withdrawn, or deleted, so the cached
  # number always matches the current records. Recounting (not incrementing)
  # means it's safe to call more than once and self-heals on removal.
  # @param feed [Feed] the feed whose day to refresh
  # @param date [Date] the repost date to recount
  def self.recompute_published(feed:, date:)
    count = feed.posts.published.where(reposted_at: date.all_day).count
    metric = find_by(feed_id: feed.id, date: date)
    return if metric.nil? && count.zero?

    metric ||= new(feed_id: feed.id, date: date)
    metric.update!(published_posts_count: count)
  end
end
