class FeedPreview < ApplicationRecord
  PREVIEW_POSTS_LIMIT = 10

  belongs_to :user
  belongs_to :feed_profile

  enum :status, {
    pending: 0,
    processing: 1,
    ready: 2,
    failed: 3
  }

  validates :url, presence: true, format: {
    with: UrlValidator.validation_regex,
    message: "must be a valid HTTP or HTTPS URL"
  }
  validates :feed_profile, presence: true
  validates :url, uniqueness: { scope: :feed_profile_id }

  normalizes :url, with: ->(url) { url.to_s.strip }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_cache_key, ->(url, feed_profile_id) { where(url: url, feed_profile_id: feed_profile_id) }

  def processing?
    pending? || status == "processing"
  end

  def ready?
    status == "ready"
  end

  # Atomically enqueue job if preview is pending and not already processing
  def enqueue_job_if_needed!
    # Use compare-and-swap pattern with database locking
    with_lock do
      if pending?
        update!(status: :processing)
        FeedPreviewJob.perform_later(id)
        true
      else
        false
      end
    end
  end

  def posts_data
    return [] unless data.present? && ready?

    data["posts"] || []
  end

  def posts_count
    posts_data.size
  end

  def cache_key_params
    { url: url, feed_profile_id: feed_profile_id }
  end

  def self.find_or_create(url:, feed_profile:, user:)
    create_with(user: user, status: :pending)
      .find_or_create_by(url: url, feed_profile: feed_profile)
  end
end
