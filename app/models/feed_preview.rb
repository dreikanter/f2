class FeedPreview < ApplicationRecord
  PREVIEW_POSTS_LIMIT = 10

  belongs_to :user

  enum :status, {
    pending: 0,
    processing: 1,
    ready: 2,
    failed: 3
  }

  validates :url, presence: true
  validates :url, uniqueness: { scope: :feed_profile_key }
  validates :feed_profile_key, presence: true
  validates :feed_profile_key, inclusion: { in: ->(_) { FeedProfile.all } }, if: -> { feed_profile_key.present? }

  validate :url_must_be_valid

  normalizes :url, with: ->(url) { url.to_s.strip }

  scope :for_cache_key, ->(url, feed_profile_key) { where(url: url, feed_profile_key: feed_profile_key) }

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
