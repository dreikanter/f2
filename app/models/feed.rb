class Feed < ApplicationRecord
  NAME_MAX_LENGTH = 40
  DESCRIPTION_MAX_LENGTH = 100
  TARGET_GROUP_PATTERN = /\A[a-z0-9_-]+\z/.freeze
  TARGET_GROUP_MAX_LENGTH = 80

  SCHEDULE_INTERVALS = {
    "10m" => { cron: "*/10 * * * *", display: "10 minutes" },
    "20m" => { cron: "*/20 * * * *", display: "20 minutes" },
    "30m" => { cron: "*/30 * * * *", display: "30 minutes" },
    "1h" => { cron: "0 * * * *", display: "1 hour" },
    "2h" => { cron: "0 */2 * * *", display: "2 hours" },
    "6h" => { cron: "0 */6 * * *", display: "6 hours" },
    "12h" => { cron: "0 */12 * * *", display: "12 hours" },
    "1d" => { cron: "0 0 * * *", display: "1 day" },
    "2d" => { cron: "0 0 */2 * *", display: "2 days" }
  }.freeze

  # Pre-selected interval for the "Check for new posts every" dropdown when a
  # feed has no schedule yet. Must be a key in SCHEDULE_INTERVALS.
  DEFAULT_SCHEDULE_INTERVAL = "2h"

  # Consecutive refresh failures that trip the auto-disable. A reachable source
  # resets the streak, so this only fires for a source that's broken run after
  # run (dead URL, persistent 5xx, etc.), not the occasional hiccup.
  MAX_CONSECUTIVE_FAILURES = 10

  belongs_to :user
  belongs_to :access_token, optional: true
  belongs_to :ai_credential, optional: true
  belongs_to :search_credential, optional: true

  has_one :feed_schedule, dependent: :destroy
  has_one :webhook_endpoint, dependent: :destroy

  has_many :events, as: :subject, dependent: :destroy
  has_many :feed_entries, dependent: :destroy
  has_many :feed_metrics, dependent: :destroy
  has_many :llm_usages, dependent: :destroy
  has_many :posts, dependent: :destroy

  enum :state, {
    draft: 0,
    disabled: 1,
    enabled: 2
  }, default: :draft

  # Set true by the edit controller only after a settled detection confirmed the
  # new source (spec §4). Lets `source_change_reverified` reject a Mode A source
  # move that never passed through identification.
  attr_accessor :source_verified

  after_update :create_schedule_on_enable
  before_validation :compose_import_after_from_parts

  validates :name, uniqueness: { scope: :user_id }, length: { maximum: NAME_MAX_LENGTH }
  validates :name, presence: true, if: :enabled?

  validates :cron_expression, presence: true, if: -> { enabled? && scheduled? }
  validates :feed_profile_key, presence: true
  validates :feed_profile_key, inclusion: { in: ->(_) { FeedProfile.all } }, if: -> { feed_profile_key.present? }

  normalizes :name, with: ->(name) { name.to_s.strip }
  normalizes :cron_expression, with: ->(cron) { cron.to_s.strip }
  normalizes :description, with: ->(desc) { desc.to_s.gsub(/\s+/, " ").strip }
  normalizes :target_group, with: ->(group) { group.present? ? group.to_s.strip.downcase : nil }

  validate :cron_expression_is_valid
  validate :params_against_profile_schema
  validate :ai_credential_belongs_to_user
  validate :search_credential_belongs_to_user
  validate :access_token_belongs_to_user
  validate :ai_credential_required_when_enabled_ai_profile, if: :enabled?
  validate :search_credential_required_when_enabled_ai_profile, if: :enabled?
  validate :engine_fixed_on_edit
  validate :source_change_reverified
  validates :access_token, presence: true, if: :enabled?
  validate :access_token_active_when_enabled, if: -> { enabled? && will_save_change_to_state? }
  validates :target_group, presence: true, if: :enabled?

  validates :target_group,
            length: { maximum: TARGET_GROUP_MAX_LENGTH },
            format: {
              with: TARGET_GROUP_PATTERN,
              message: "must contain only lowercase letters, numbers, underscores and dashes"
            },
            allow_blank: true

  scope :due, -> {
    joins(:feed_schedule)
      .where("feed_schedules.next_run_at <= ?", Time.current)
      .where(state: :enabled)
  }

  def self.schedule_intervals_for_select
    SCHEDULE_INTERVALS.map { |key, config| [config[:display], key] }
  end

  def schedule_interval
    SCHEDULE_INTERVALS.find { |_key, config| config[:cron] == cron_expression }&.first
  end

  def schedule_interval=(key)
    self.cron_expression = SCHEDULE_INTERVALS.dig(key, :cron)
  end

  # Form-facing accessors splitting import_after into a checkbox plus
  # separate date and time inputs. The checkbox drives everything: when it's
  # off, import_after resets to nil no matter what the date and time fields
  # contain. The setters only record their part; import_after itself is
  # composed once in before_validation — composing on every part-write let
  # earlier parts read fallbacks from a half-updated import_after, making the
  # result depend on assignment order.
  def import_after_enabled
    return @import_after_enabled unless @import_after_enabled.nil?

    import_after.present?
  end

  def import_after_enabled=(value)
    @import_after_parts_assigned = true
    @import_after_enabled = ActiveModel::Type::Boolean.new.cast(value) || false
  end

  def import_after_date
    @import_after_date || import_after&.strftime("%Y-%m-%d")
  end

  def import_after_date=(value)
    @import_after_parts_assigned = true
    @import_after_date = value.to_s.strip
  end

  def import_after_time
    @import_after_time || import_after&.strftime("%H:%M")
  end

  def import_after_time=(value)
    @import_after_parts_assigned = true
    @import_after_time = value.to_s.strip
  end

  # Link to the target group on its FreeFeed instance. Post#freefeed_url
  # builds on top of this to point at individual published posts.
  def target_group_url
    return unless access_token && target_group.present?

    "#{access_token.host}/#{target_group}"
  end

  def url
    params&.dig("url")
  end

  def url=(value)
    next_params = (params || {}).dup
    if value.nil?
      next_params.delete("url")
    else
      next_params["url"] = value.is_a?(String) ? value.strip : value
    end
    self.params = next_params
  end

  # Whichever param the profile uses as the user-facing source (url, prompt, …).
  # Used by views that need to show "what the user typed" without caring about
  # the underlying input shape. Driven by the profile's declared source key so
  # smuggled keys in the params jsonb can't disguise the real source.
  def source_input
    FeedProfile.source_input_for(feed_profile_key, params)
  end

  # Whether the user's source is a URL rather than a free-text prompt.
  # Decided purely by parsing the input (no profile lookup, no LLM), so the
  # label stays accurate even when an AI profile is chosen for a URL source.
  def source_input_url?
    SourceLink.url?(source_input)
  end

  def display_name
    name.presence || "Untitled feed"
  end

  def feed_profile_present?
    feed_profile_key.present? && FeedProfile.exists?(feed_profile_key)
  end

  # Resolves and returns the loader class for this feed
  # @return [Class] the loader class
  def loader_class
    FeedProfile.loader_class_for(feed_profile_key)
  end

  # Resolves and returns the processor class for this feed
  # @return [Class] the processor class
  def processor_class
    FeedProfile.processor_class_for(feed_profile_key)
  end

  # Resolves and returns the normalizer class for this feed
  # @return [Class] the normalizer class
  def normalizer_class
    FeedProfile.normalizer_class_for(feed_profile_key)
  end

  def scheduled?
    FeedProfile.scheduled?(feed_profile_key)
  end

  # True for push-ingested profiles (webhook): there is no source input, so
  # source-driven surfaces — source field, detection, preview — don't apply.
  def sourceless?
    FeedProfile.source_key_for(feed_profile_key).nil?
  end

  def can_be_enabled?
    name.present? && access_token&.active? && target_group.present? && feed_profile_present? &&
      (!scheduled? || cron_expression.present?) && ai_enablement_requirements_met?
  end

  # Promote the feed to enabled, running the enabled-state validators. If
  # validation fails, the DB stays at the prior state, errors are added to the
  # feed, and the in-memory state is rolled back to its persisted value so
  # re-renders reflect DB truth.
  def enable
    transition_state(:enabled)
  end

  def disable
    transition_state(:disabled)
  end

  def can_be_previewed?
    return false unless source_input.present? && feed_profile_present?
    return true unless FeedProfile.depends_on_ai?(feed_profile_key)
    return false unless ai_credential&.active?
    return false unless search_credential&.active?

    # A dropped model no longer blocks preview — a run resolves to the
    # credential's default supported model, so preview only needs some verified
    # model to exist (spec §5).
    ai_credential.supported_models.any?
  end

  # True when the feed's chosen model is still in the matrix ∩ credential
  # snapshot. This is the one availability rule every surface reads from.
  def ai_model_supported?
    ai_credential.present? && ai_credential.supports_model?(ai_model)
  end

  # The model an AI run/preview actually uses with `credential`: the chosen one
  # when still supported, otherwise the credential's default supported model.
  # Never hard-fails on a dropped model — the caller records the fallback so the
  # feed page can prompt a re-pick (spec §5).
  def effective_ai_model(credential = ai_credential)
    return ai_model if credential.nil?
    return ai_model if credential.supports_model?(ai_model)

    credential.default_supported_model
  end

  # Records a one-time notice that the saved model dropped out and a fallback is
  # in use, so the feed page can nudge a re-pick. Deduped by the dropped→fallback
  # pair so repeated runs don't spam the activity log.
  def note_ai_model_fallback!(from:, to:)
    return if events.where(type: "feed_ai_model_unavailable").not_expired.exists?(
      ["metadata->>'dropped_model' = ? AND metadata->>'fallback_model' = ?", from.to_s, to.to_s]
    )

    Event.create!(
      type: "feed_ai_model_unavailable",
      level: :warning,
      subject: self,
      user: user,
      metadata: { dropped_model: from, fallback_model: to }
    )
  end

  # Records that an AI gather came back empty, so the structure call was skipped
  # and the run produced nothing (spec §6/§8). Debug level keeps this routine,
  # expected outcome out of the user event feed while leaving it visible to
  # operators. No-op for an unpersisted (preview) feed.
  def note_ai_gather_empty!
    return unless persisted?

    Event.create!(
      type: "feed_refresh_ai_empty",
      level: :debug,
      subject: self,
      user: user
    )
  end

  # Creates and returns a loader instance for this feed
  # @param options [Hash] loader options (e.g. a shared :http_client)
  # @return [Loader::Base] loader instance
  def loader_instance(options = {})
    loader_class.new(self, options)
  end

  # Creates and returns a processor instance for this feed
  # @param raw_data [String] raw feed data to process
  # @return [Processor::Base] processor instance
  def processor_instance(raw_data)
    processor_class.new(self, raw_data)
  end

  # Creates and returns a normalizer instance for the given feed entry
  # @param feed_entry [FeedEntry] the feed entry to normalize
  # @return [Normalizer::Base]
  def normalizer_instance(feed_entry)
    normalizer_class.new(feed_entry)
  end

  # Returns the date when the feed was last refreshed
  # @return [Time, nil] last refresh time or nil if never refreshed
  def last_refreshed_at
    feed_entries.maximum(:created_at)
  end

  # Returns the date of the most recent imported post
  # @return [Time, nil] most recent post date or nil if no posts
  def most_recent_post_date
    posts.maximum(:published_at)
  end

  # Returns the time of the most recent repost (publication to FreeFeed),
  # regardless of the original source publication date.
  # @return [Time, nil] most recent repost time or nil if no published posts
  def most_recent_repost_at
    posts.published.maximum(:reposted_at)
  end

  # Returns the count of posts published in the last week (by source date)
  # @return [Integer] number of posts published in the last week
  def posts_published_last_week_count
    posts.where(published_at: 1.week.ago.beginning_of_day..Time.current.end_of_day).count
  end

  # Single source of truth for the cached post counters. Post's create/destroy
  # callbacks keep these current on single-record writes; bulk paths that skip
  # those callbacks (FeedRefreshWorkflow's insert_all) must call these to resync.
  def recount_imported_posts!
    update_column(:imported_posts_count, posts.count)
  end

  def recount_published_posts!
    update_column(:published_posts_count, posts.published.count)
  end

  # Makes the existing schedule due immediately (next_run_at = now). No-op for
  # a feed without one — the schedule is created when the feed is enabled.
  def reset_schedule!
    feed_schedule&.update!(next_run_at: Time.current)
  end

  # Creates the schedule pointed at the next cron slot, without triggering an
  # immediate run. Only called when a feed gains its schedule on enable
  # (create_schedule_on_enable guards the already-scheduled case).
  # @return [FeedSchedule]
  def defer_schedule!
    schedule = build_feed_schedule(last_run_at: Time.current)
    schedule.next_run_at = schedule.calculate_next_run_at
    schedule.save!
    schedule
  end

  # Bumps the failure streak after a failed refresh and turns the feed off once
  # it hits the threshold. Returns true when this call disabled it. Skips the
  # disable if the feed was already disabled elsewhere this run (e.g. a
  # credential auth error), so we never disable twice.
  def record_refresh_failure!
    increment!(:consecutive_failures)
    return false if consecutive_failures < MAX_CONSECUTIVE_FAILURES
    return false unless reload.enabled?

    disable_after_repeated_failures!
    true
  end

  # Disables just this feed (not the whole token) and logs why, so the user can
  # fix the target group and re-enable. `reason` is a deterministic code the UI
  # maps to safe copy; `details` is the raw FreeFeed response, kept for diagnostics.
  def disable_due_to_unavailable_target!(reason: nil, details: nil)
    metadata = { reason: reason&.to_s, target_group: target_group, details: details }.compact
    disable_with_event!("feed_target_group_unavailable", metadata)
  end

  # Disables the feed and records why in one transaction. Already-disabled feeds
  # are left untouched so callers can safely race or retry without duplicate events.
  # update_columns flips the state and zeroes the counter in one write, skipping
  # validations neither needs; metadata is evaluated first, so it can read
  # pre-disable values like the failure streak.
  def disable_with_event!(type, metadata)
    return false if disabled?

    transaction do
      update_columns(state: self.class.states[:disabled], consecutive_failures: 0)
      Event.create!(type: type, level: :warning, subject: self, user: user, metadata: metadata)
    end
  end

  # Clears the streak after a successful refresh.
  def reset_refresh_failures!
    return if consecutive_failures.zero?

    update_column(:consecutive_failures, 0)
  end

  private

  def transition_state(new_state)
    self.state = new_state
    return true if save

    self.state = state_was
    false
  end

  def ai_enablement_requirements_met?
    return true unless FeedProfile.depends_on_ai?(feed_profile_key)

    ai_credential&.active? && search_credential&.active? && ai_model.present?
  end

  # Records a feed_auto_disabled event stamped with the streak length, so the
  # activity log shows how many failures it took.
  def disable_after_repeated_failures!
    disable_with_event!("feed_auto_disabled", { error_count: consecutive_failures })
  end

  # Only touches import_after when the form parts were assigned, so saves that
  # never saw the checkbox (state flips, background updates) leave it alone.
  def compose_import_after_from_parts
    return unless @import_after_parts_assigned

    self.import_after = compose_import_after
  end

  # Builds import_after from the date and time parts. Time defaults to midnight
  # when omitted. Rather than rejecting a missing or unparseable date, we fall
  # back to the current moment so the user never has to fix a validation error.
  def compose_import_after
    return nil unless import_after_enabled

    Time.zone.strptime("#{import_after_date} #{import_after_time.presence || '00:00'}", "%Y-%m-%d %H:%M")
  rescue ArgumentError
    Time.current
  end

  def cron_expression_is_valid
    return if cron_expression.blank?

    parsed_cron = Fugit.parse(cron_expression)
    errors.add(:cron_expression, "is not a valid cron expression") unless parsed_cron
  end

  # Structural sanity check: in normal use the form is generated from the
  # same parameter_schema, so this can only fire on a forged POST or a code
  # bug. The "<pointer> <message>" output is machine-only; the future
  # per-field form renderer translates it; nothing surfaces raw to users.
  def params_against_profile_schema
    return unless feed_profile_present?

    schema = FeedProfile.parameter_schema_for(feed_profile_key)
    return if schema.blank?

    JSONSchemer.schema(schema, format: true).validate(params || {}).each do |error|
      pointer = error["data_pointer"].to_s
      message = pointer.empty? ? error["error"] : "#{pointer} #{error['error']}"
      errors.add(:params, message)
    end
  end

  def ai_credential_belongs_to_user
    return if ai_credential.nil?
    return if user_id.nil?
    return if ai_credential.user_id == user_id

    errors.add(:ai_credential, "must belong to the same user")
  end

  def search_credential_belongs_to_user
    return if search_credential.nil?
    return if user_id.nil?
    return if search_credential.user_id == user_id

    errors.add(:search_credential, "must belong to the same user")
  end

  def access_token_belongs_to_user
    return if access_token.nil?
    return if user_id.nil?
    return if access_token.user_id == user_id

    errors.add(:access_token, "must belong to the same user")
  end

  # The engine (deterministic vs AI) is fixed at creation: an existing feed never
  # switches across the AI boundary in edit — you create a new feed instead (spec
  # §4). A deterministic → deterministic profile change is fine.
  def engine_fixed_on_edit
    return unless persisted? && feed_profile_key_changed?
    return unless FeedProfile.exists?(feed_profile_key) && FeedProfile.exists?(feed_profile_key_was)
    return if FeedProfile.depends_on_ai?(feed_profile_key) == FeedProfile.depends_on_ai?(feed_profile_key_was)

    errors.add(:feed_profile_key, "can't switch between AI and non-AI feeds — start a new feed instead")
  end

  # A deterministic feed's source can only move through identification (spec §4):
  # the edit controller re-runs detection and sets `source_verified` once a
  # working candidate confirms the new source. This blocks a forged direct edit
  # from silently pointing a live feed at an unverified, possibly-broken source.
  def source_change_reverified
    return unless persisted?
    return if draft? || source_verified
    return if FeedProfile.depends_on_ai?(feed_profile_key)
    return unless source_input_changed_in_place?

    errors.add(:base, "The source changed — re-check it before saving.")
  end

  def source_input_changed_in_place?
    return false unless params_changed?

    key = FeedProfile.source_key_for(feed_profile_key)
    before, after = params_change
    before&.dig(key) != after&.dig(key)
  end

  # A feed may only become enabled while its token is active, matching
  # can_be_enabled?. Presence alone let the edit form enable a feed whose token
  # had been deactivated, while the feed page's Enable button refused. Scoped to
  # the state change: an already-enabled feed still saves while its token is
  # mid-revalidation (validating is a routine stop for a live token). nil is
  # left to the presence validator.
  def access_token_active_when_enabled
    return if access_token.nil? || access_token.active?

    errors.add(:access_token, "must be active (currently #{access_token.status})")
  end

  def ai_credential_required_when_enabled_ai_profile
    return unless feed_profile_present?
    return unless FeedProfile.depends_on_ai?(feed_profile_key)

    if ai_credential.nil?
      errors.add(:ai_credential, "must be selected for AI-backed feeds")
    elsif !ai_credential.active?
      errors.add(:ai_credential, "must be active (currently #{ai_credential.state})")
    elsif ai_model.blank?
      errors.add(:ai_model, "Choose a model for this feed.")
    elsif ai_model_changed? && !ai_model_supported?
      # Membership is enforced only on the change that sets it, so a later-dropped
      # model never traps an unrelated edit — runs fall back gracefully instead.
      errors.add(:ai_model, "This model isn't available anymore. Pick another one.")
    end
  end

  def search_credential_required_when_enabled_ai_profile
    return unless feed_profile_present?
    return unless FeedProfile.depends_on_ai?(feed_profile_key)

    if search_credential.nil?
      errors.add(:search_credential, "must be selected for AI-backed feeds")
    elsif !search_credential.active?
      errors.add(:search_credential, "must be active (currently #{search_credential.state})")
    end
  end

  def create_schedule_on_enable
    return unless saved_change_to_state?
    return unless enabled?
    return unless scheduled?
    return if feed_schedule.present?

    defer_schedule!
  end
end
