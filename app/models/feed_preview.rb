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

  def self.fresh_ready(user_id:, feed_profile_key:, params:, within:)
    where(user_id: user_id, feed_profile_key: feed_profile_key, params_digest: digest_for(feed_profile_key, params))
      .ready
      .where(ready_at: within.ago..)
      .order(ready_at: :desc)
      .first
  end

  def posts_data
    (data.present? && ready? && data["posts"]) || []
  end

  def posts_count
    posts_data.size
  end

  private

  def assign_params_digest
    self[:params_digest] = self.class.digest_for(feed_profile_key, params)
  end
end
