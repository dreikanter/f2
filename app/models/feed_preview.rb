class FeedPreview < ApplicationRecord
  PREVIEW_POSTS_LIMIT = 10
  POLLING_INTERVAL_MS = 2500
  TIMEOUT_AFTER = 85.seconds
  AI_TIMEOUT_AFTER = 4.minutes

  # How long a ready preview is reused before a fresh run is forced.
  PREVIEW_FRESHNESS_WINDOW = 60.minutes

  belongs_to :user
  belongs_to :feed, optional: true
  belongs_to :ai_credential, optional: true
  belongs_to :search_credential, optional: true

  enum :status, { pending: 0, processing: 1, ready: 2, failed: 3 }

  validates :feed_profile_key, presence: true
  validate :feed_belongs_to_user
  validates :feed_profile_key, inclusion: { in: ->(_) { FeedProfile.all } }, if: -> { feed_profile_key.present? }

  before_validation :assign_params_digest, if: :preview_identity_changed?

  # A preview's identity is what the user supplied: the source input behind the
  # profile's source key, plus the profile options they set. Params derived
  # later during processing must not change identity, so only declared option
  # keys join it, sorted to survive hash key-ordering and jsonb read-ordering.
  #
  # For AI profiles the chosen credentials + model join the identity, so changing
  # either provider selection doesn't reuse a cached result.
  # Saved feeds have separate previews so each run retains its cost attribution.
  #
  # JSON-encode the parts before hashing so their boundaries are unambiguous:
  # otherwise ["ab", "c"] and ["a", "bc"] would hash alike.
  def self.digest_for(
    feed_profile_key,
    params,
    feed_id: nil,
    ai_credential_id: nil,
    ai_model: nil,
    search_credential_id: nil
  )
    parts = [FeedProfile.source_input_for(feed_profile_key, params), ai_credential_id, ai_model, search_credential_id]
    # Append only when set, so profiles without options keep their digests.
    options = option_parts_for(feed_profile_key, params)
    parts << options if options.any?
    parts << ["feed", feed_id] if feed_id.present?
    Digest::SHA256.hexdigest(parts.to_json)
  end

  # @param feed_profile_key [String] the profile key
  # @param params [Hash, nil] the preview params
  # @return [Array<Array>] declared option name/value pairs, sorted by name
  def self.option_parts_for(feed_profile_key, params)
    names = FeedProfile.options_for(feed_profile_key).map(&:name)
    (params || {}).slice(*names).sort.to_a
  end

  # Clears the last result and queues a fresh run. run_id rotates so a job still
  # in flight for the previous run can't write its result over this one.
  # @return [FeedPreview] self, persisted and pending
  def restart!
    update!(status: :pending, data: nil, ready_at: nil, run_id: SecureRandom.uuid)
    FeedPreviewJob.perform_later(id, run_id)
    FeedPreviewTimeoutJob.set(wait_until: updated_at + timeout_after).perform_later(id, run_id)
    self
  end

  # Matching run_id makes a superseded run's timeout harmless. Rotating it keeps
  # the matching worker from writing results after the timeout.
  # @param run_id [String] the run token captured when the timeout was scheduled
  # @return [FeedPreview] self
  def timeout!(run_id:)
    updated = self.class
                  .where(id: self.id)
                  .where(run_id: run_id)
                  .where(status: [:pending, :processing])
                  .update_all(status: :failed, run_id: SecureRandom.uuid, updated_at: Time.current)
    reload if updated.positive?
    self
  end

  def timeout_after
    FeedProfile.depends_on_ai?(feed_profile_key) ? AI_TIMEOUT_AFTER : TIMEOUT_AFTER
  end

  # The first poll is immediate. Two extra polls leave one interval for Solid
  # Queue to dispatch a due timeout and let the final poll render its result.
  def polling_max_polls
    timeout_after.in_milliseconds.div(POLLING_INTERVAL_MS) + 2
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

  def feed_belongs_to_user
    errors.add(:feed, "must belong to the same user") if feed && feed.user_id != user_id
  end

  def preview_identity_changed?
    new_record? ||
      will_save_change_to_feed_id? ||
      will_save_change_to_feed_profile_key? ||
      will_save_change_to_params? ||
      will_save_change_to_ai_credential_id? ||
      will_save_change_to_ai_model? ||
      will_save_change_to_search_credential_id?
  end

  def assign_params_digest
    self[:params_digest] = self.class.digest_for(
      feed_profile_key,
      params,
      feed_id:,
      ai_credential_id:,
      ai_model:,
      search_credential_id:
    )
  end
end
