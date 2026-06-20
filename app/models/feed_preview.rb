class FeedPreview < ApplicationRecord
  PREVIEW_POSTS_LIMIT = 10

  belongs_to :user
  belongs_to :feed, optional: true

  enum :status, { pending: 0, processing: 1, ready: 2, failed: 3 }

  validates :feed_profile_key, presence: true
  validates :feed_profile_key, inclusion: { in: ->(_) { FeedProfile.all } }, if: -> { feed_profile_key.present? }

  before_validation :assign_params_digest

  # A preview's identity is the user-provided source input (the value behind the
  # profile's input_shape) — NOT the whole params hash. User input for a new feed
  # is intentionally minimal (one field today); params derived later during
  # processing must not change identity. Hashing that single value also sidesteps
  # hash key-ordering (and jsonb read-ordering) entirely. When user-supplied input
  # grows beyond one field, extend this to cover the new user fields (still not
  # the derived ones).
  def self.digest_for(feed_profile_key, params)
    Digest::SHA256.hexdigest(source_input(feed_profile_key, params).to_s)
  end

  # The user-facing source value for a profile, selected by its input_shape.
  def self.source_input(feed_profile_key, params)
    shape = FeedProfile[feed_profile_key]&.dig(:input_shape) || :url
    (params || {})[shape.to_s]
  end

  # Transitions to :failed only if still non-terminal. The status guard in the
  # UPDATE means a concurrently completing job won't be clobbered.
  def timeout!
    updated = self.class
                  .where(id: self.id)
                  .where(status: [:pending, :processing])
                  .update_all(status: :failed, updated_at: Time.current)
    reload if updated.positive?
  end

  def posts_data
    (data.present? && ready? && data["posts"]) || []
  end

  def posts_count
    posts_data.size
  end

  # Total items found in the source — the full batch the loader pulled, not just
  # the handful shown in the preview. This is an upper bound on what enabling the
  # feed enqueues; the refresh later drops duplicates and entries before the
  # import threshold. Falls back to the preview count for older records without
  # recorded stats.
  def total_entries_count
    return 0 unless data.present? && ready?

    data.dig("stats", "total_entries") || posts_count
  end

  private

  def assign_params_digest
    self[:params_digest] = self.class.digest_for(feed_profile_key, params)
  end
end
