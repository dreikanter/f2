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

  def self.find_or_create_for_preview(url:, feed_profile:, user:)
    # Use transaction with retry logic to handle race conditions
    transaction do
      # Try to find existing preview first
      existing = where(url: url, feed_profile: feed_profile).first

      # Return existing if it's recent (within 1 hour)
      return existing if existing&.created_at&.> 1.hour.ago

      # Remove old preview if exists
      existing&.destroy

      # Create new preview with unique constraint protection
      create!(
        url: url,
        feed_profile: feed_profile,
        user: user,
        status: :pending
      )
    end
  rescue ActiveRecord::RecordNotUnique
    # If we hit the unique constraint, someone else created it, so fetch it
    where(url: url, feed_profile: feed_profile).first!
  end
end
