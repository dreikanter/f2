class FeedPreview < ApplicationRecord
  include PolledRun

  PREVIEW_POSTS_LIMIT = 10
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

  def needs_run?
    new_record? || stale_ready?
  end

  def stale_ready?
    ready? && ready_at.present? && ready_at < PREVIEW_FRESHNESS_WINDOW.ago
  end

  def current_configuration?
    params_digest == calculated_params_digest
  end

  # A preview's identity includes the profile configuration and what the user
  # supplied: the source input and the profile options they set. Params derived
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
    parts << FeedProfile.configuration_digest(feed_profile_key)
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
    FeedPreviewJob.perform_later(id, run_id, params_digest)
    FeedPreviewTimeoutJob.set(wait_until: updated_at + timeout_after).perform_later(id, run_id)
    self
  end

  # @param run_id [String] the run token captured when the timeout was scheduled
  # @return [FeedPreview] self
  def timeout!(run_id:)
    settle_timeout!(run_id: run_id, status: :failed, from: [:pending, :processing])
  end

  def timeout_after
    FeedProfile.depends_on_ai?(feed_profile_key) ? AI_TIMEOUT_AFTER : TIMEOUT_AFTER
  end

  # AI runs get a longer deadline, so the poll count follows the run's own.
  def polling_max_polls
    self.class.polls_within(timeout_after)
  end

  def posts_data
    (data.present? && ready? && data["posts"]) || []
  end

  def posts_count
    posts_data.size
  end

  # Total items found in the source: the full batch the loader pulled, not just
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
    self[:params_digest] = calculated_params_digest
  end

  def calculated_params_digest
    self.class.digest_for(
      feed_profile_key,
      params,
      feed_id:,
      ai_credential_id:,
      ai_model:,
      search_credential_id:
    )
  end
end
