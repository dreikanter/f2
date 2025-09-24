class FeedPreview < ApplicationRecord
  PREVIEW_POSTS_LIMIT = 10

  belongs_to :user
  belongs_to :feed, optional: true
  belongs_to :feed_profile

  enum :status, {
    pending: 0,
    processing: 1,
    ready: 2,
    failed: 3
  }

  validates :url, presence: true
  validate :url_must_be_valid

  validates :feed_profile, presence: true
  validates :url, uniqueness: { scope: :feed_profile_id }

  normalizes :url, with: ->(url) { url.to_s.strip }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_cache_key, ->(url, feed_profile_id) { where(url: url, feed_profile_id: feed_profile_id) }

  def posts_data
    (data.present? && ready? && data["posts"]) || []
  end

  def posts_count
    posts_data.size
  end

  private

  def url_must_be_valid
    return if url.blank?

    unless UrlValidator.valid?(url)
      errors.add(:url, "must be a valid HTTP or HTTPS URL")
    end
  end
end
