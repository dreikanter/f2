class FeedPreview < ApplicationRecord
  PREVIEW_POSTS_LIMIT = 10

  # How long a ready preview is reused before a fresh run is forced.
  PREVIEW_FRESHNESS_WINDOW = 60.minutes

  belongs_to :user
  belongs_to :ai_credential, optional: true

  enum :status, { pending: 0, processing: 1, ready: 2, failed: 3 }

  validates :feed_profile_key, presence: true
  validates :feed_profile_key, inclusion: { in: ->(_) { FeedProfile.all } }, if: -> { feed_profile_key.present? }

  attr_accessor :search_credential_id_for_digest

  before_validation :assign_params_digest, if: :preview_identity_changed?

  # A preview's identity is the user-provided source input (the value behind the
  # profile's source key) — NOT the whole params hash. User input for a new feed
  # is intentionally minimal (one field today); params derived later during
  # processing must not change identity. Hashing that single value also sidesteps
  # hash key-ordering (and jsonb read-ordering) entirely. When user-supplied input
  # grows beyond one field, extend this to cover the new user fields (still not
  # the derived ones).
  #
  # For AI profiles the chosen credentials + model join the identity, so changing
  # either provider selection doesn't reuse a cached result.
  #
  # JSON-encode the parts before hashing so their boundaries are unambiguous:
  # otherwise ["ab", "c"] and ["a", "bc"] would hash alike.
  def self.digest_for(feed_profile_key, params, ai_credential_id = nil, ai_model = nil, search_credential_id = nil)
    parts = [FeedProfile.source_input_for(feed_profile_key, params), ai_credential_id, ai_model, search_credential_id]
    Digest::SHA256.hexdigest(parts.to_json)
  end

  # Transitions to :failed only if still non-terminal. Rotating run_id makes the
  # timeout terminal (spec §6): the still-running job holds the old run_id, so its
  # run_id-gated transitions now update 0 rows and can't flip the row back to
  # :ready after the user has already seen the timeout and left.
  def timeout!
    updated = self.class
                  .where(id: self.id)
                  .where(status: [:pending, :processing])
                  .update_all(status: :failed, run_id: SecureRandom.uuid, updated_at: Time.current)
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

  def preview_identity_changed?
    new_record? ||
      will_save_change_to_feed_profile_key? ||
      will_save_change_to_params? ||
      will_save_change_to_ai_credential_id? ||
      will_save_change_to_ai_model? ||
      search_credential_id_for_digest.present?
  end

  def assign_params_digest
    self[:params_digest] = self.class.digest_for(
      feed_profile_key,
      params,
      ai_credential_id,
      ai_model,
      resolved_search_credential_id_for_digest
    )
  end

  def resolved_search_credential_id_for_digest
    return search_credential_id_for_digest if search_credential_id_for_digest.present?
    return unless new_record? && user && FeedProfile.exists?(feed_profile_key)
    return unless FeedProfile.depends_on_ai?(feed_profile_key)

    credentials = user.search_credentials.active
    credentials.find_by(id: user.default_search_credential_id)&.id || credentials.pick(:id)
  end
end
