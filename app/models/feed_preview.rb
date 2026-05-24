class FeedPreview < ApplicationRecord
  PREVIEW_POSTS_LIMIT = 10

  belongs_to :user
  belongs_to :feed, optional: true

  enum :status, { pending: 0, processing: 1, ready: 2, failed: 3 }

  validates :feed_profile_key, presence: true
  validates :feed_profile_key, inclusion: { in: ->(_) { FeedProfile.all } }, if: -> { feed_profile_key.present? }

  before_validation :assign_params_digest

  # Canonical digest of the source params. Must match Feed#params_digest so the
  # enable gate (reader) and the preview (writer) agree on identity.
  def self.digest_for(params)
    canonical = (params || {}).deep_stringify_keys.sort.to_h.to_json
    Digest::SHA256.hexdigest(canonical)
  end

  def self.fresh_ready(user_id:, feed_profile_key:, params:, within:)
    where(user_id: user_id, feed_profile_key: feed_profile_key, params_digest: digest_for(params))
      .ready
      .where(ready_at: within.ago..)
      .order(ready_at: :desc)
      .first
  end

  def params_digest
    self.class.digest_for(params)
  end

  def posts_data
    (data.present? && ready? && data["posts"]) || []
  end

  def posts_count
    posts_data.size
  end

  private

  def assign_params_digest
    self[:params_digest] = self.class.digest_for(params)
  end
end
