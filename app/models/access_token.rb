class AccessToken < ApplicationRecord
  belongs_to :user
  has_many :feeds
  has_one :access_token_detail, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :token, presence: true, on: :create
  validates :host, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid HTTP or HTTPS URL" }

  enum :state, { pending: 0, validating: 1, active: 2, inactive: 3 }

  before_validation :generate_default_name, if: -> { name.blank? }
  before_destroy :disable_associated_feeds
  after_destroy :forget_rate_limit_state

  encrypts :encrypted_token

  attr_accessor :token

  # Lets Feeder identify the account behind the token, via whoami and
  # managedGroups. Without it there is nothing to validate.
  READ_MY_INFO_SCOPE = "read-my-info".freeze

  # Lets Feeder read a group's subscriber count.
  READ_USERS_INFO_SCOPE = "read-users-info".freeze

  # Lets Feeder publish posts and comments on the user's behalf.
  MANAGE_POSTS_SCOPE = "manage-posts".freeze

  TOKEN_SCOPES = [
    READ_MY_INFO_SCOPE,
    READ_USERS_INFO_SCOPE,
    MANAGE_POSTS_SCOPE
  ].freeze

  def self.token_url(domain)
    "https://#{domain}/settings/app-tokens/create?scopes=#{TOKEN_SCOPES.join('%20')}"
  end

  # SQL counterpart of #allows_scope?. Keep the two in step.
  scope :allowing_scope, ->(scope) {
    where("scopes @> ARRAY[?]::varchar[]", scope)
  }

  # A user can create access token record associated with a known
  # FreeFeed instances only (see Settings::AccessTokensController).
  # Though the model allows to define any valid host URL.
  FREEFEED_HOSTS = {
    production: {
      url: "https://freefeed.net",
      display_name: "freefeed.net (main)",
      domain: "freefeed.net",
      token_url: token_url("freefeed.net")
    },
    staging: {
      url: "https://candy.freefeed.net",
      display_name: "candy.freefeed.net (staging)",
      domain: "candy.freefeed.net",
      token_url: token_url("candy.freefeed.net")
    },
    beta: {
      url: "https://beta.freefeed.net",
      display_name: "beta.freefeed.net (beta)",
      domain: "beta.freefeed.net",
      token_url: token_url("beta.freefeed.net")
    }
  }.freeze

  def self.host_options_for_select
    FREEFEED_HOSTS.map { |_key, config| [config[:display_name], config[:url]] }
  end

  def self.build_with_token(attributes = {})
    defaults = {
      state: :pending,
      encrypted_token: attributes[:token],
      host: FREEFEED_HOSTS[:production][:url]
    }

    new(defaults.merge(attributes))
  end

  VALIDATION_TIMEOUT = 15.minutes
  VALIDATION_ABANDONED_EVENT_TYPE = "access_token_validation_abandoned".freeze

  def validate_token_async
    run_id = start_validation!
    TokenValidationJob.perform_later(self, run_id)
  end

  # Reserves a run without changing state while the job waits. Background
  # callers use this so publishers can keep using an active token until the
  # validation worker actually starts.
  def enqueue_validation
    run_id = SecureRandom.uuid
    update!(validation_run_id: run_id, validation_started_at: nil)
    TokenValidationJob.perform_later(self, run_id)
  end

  # Opens a new user-initiated run, superseding any older worker still in flight.
  # @param run_id [String] UUID identifying the run
  # @return [String] the run ID
  def start_validation!(run_id: SecureRandom.uuid)
    started_at = Time.current
    update!(state: :validating, validation_started_at: started_at, validation_run_id: run_id)
    schedule_validation_timeout(run_id, started_at)
    run_id
  end

  # Claims this run unless another validation has started since it was queued.
  # @param run_id [String] UUID captured when the job was enqueued
  # @return [Boolean] whether the job owns the current run
  def claim_validation!(run_id)
    with_lock do
      return false unless validation_run_id == run_id

      unless validating? && validation_started_at.present?
        started_at = Time.current
        update!(state: :validating, validation_started_at: started_at)
        schedule_validation_timeout(run_id, started_at)
      end
    end

    true
  end

  # @param run_id [String] UUID captured by the timeout job
  # @return [Boolean] whether the matching run was settled
  def timeout_validation!(run_id:)
    with_lock do
      return false unless validation_run_id == run_id && (pending? || validating?)

      update!(state: :inactive, validation_started_at: nil, validation_run_id: nil)
      Event.create!(
        type: VALIDATION_ABANDONED_EVENT_TYPE,
        user: user,
        subject: self,
        level: :warning
      )
    end

    true
  end

  # Runs a terminal write only while the caller still owns this validation.
  # @param run_id [String] UUID captured by the worker
  # @return [Boolean] whether the block ran
  def with_validation_run(run_id)
    with_lock do
      return false unless validation_run_id == run_id

      yield
    end

    true
  end

  def build_client
    FreefeedClient.new(host: host, token: encrypted_token, rate_limit_subject: rate_limit_subject)
  end

  # FreeFeed fixes an app token's scopes when it issues the token, so a missing
  # scope is permanent.
  def allows_scope?(scope)
    scopes.include?(scope)
  end

  # Points at this token's own instance rather than the default one.
  def token_creation_url
    self.class.token_url(host_domain)
  end

  # Cache of this token's postable group names, shared by the feed form's
  # group selector and the background groups refresh.
  GROUPS_CACHE_TTL = 10.minutes

  def groups_cache_key
    "access_token_groups/#{id}"
  end

  # Rate-limit identity for FreeFeed calls. FreeFeed meters per authenticated
  # account (the JWT user id), shared across that account's tokens, so we key on
  # instance + user id to collapse sibling tokens onto one bucket. The user id is
  # known only after validation; until then we fall back to a per-token subject.
  # See docs/rate-limiting.md.
  def rate_limit_subject
    if freefeed_user_id.present?
      "freefeed:#{freefeed_instance}:#{freefeed_user_id}"
    else
      "freefeed:token:#{id}"
    end
  end

  # Stable id for the targeted FreeFeed instance: the known-host key
  # (production/staging/beta), else the host domain. Canonicalized (DNS is
  # case-insensitive) so equivalent spellings don't fragment the account bucket.
  def freefeed_instance
    domain = host_domain.to_s.downcase.delete_suffix(".")
    known = FREEFEED_HOSTS.find { |_key, config| config[:domain] == domain }
    known ? known.first.to_s : domain
  end

  def host_domain
    URI.parse(host).host
  end

  # Link to a group's page on this token's FreeFeed instance. Rebuilt through
  # URI with the group name escaped as a path segment, so stored values can't
  # smuggle a scheme or extra URL parts into hrefs.
  def group_url(group_username)
    uri = URI.parse(host)
    return unless uri.is_a?(URI::HTTP)

    uri.path = "/#{CGI.escapeURIComponent(group_username.to_s)}"
    uri.query = nil
    uri.fragment = nil
    uri.to_s
  rescue URI::InvalidURIError
    nil
  end

  def display_name
    name
  end

  def provider_name
    owner.present? ? "@#{owner} at #{host_domain}" : host_domain
  end

  def disable_associated_feeds
    feeds.update_all(state: :disabled, access_token_id: nil)
  end

  # Drop the limiter bucket when this token is gone. Account-scoped subjects can
  # be shared by sibling tokens, so only forget once no sibling still uses it.
  def forget_rate_limit_state
    subject = rate_limit_subject
    return if freefeed_user_id.present? &&
              AccessToken.where(freefeed_user_id: freefeed_user_id)
                         .where.not(id: id)
                         .any? { |sibling| sibling.rate_limit_subject == subject }

    RateLimit.forget(:freefeed, subject: subject)
  end

  # `event_type` carries the reason, so a dead token and an under-permissioned
  # one read differently in the event log.
  def disable_token_and_feeds(event_type: "access_token_validation_failed", run_id: nil, attributes: {})
    with_lock do
      return false if run_id && validation_run_id != run_id

      update!(**attributes, state: :inactive, validation_started_at: nil, validation_run_id: nil)

      enabled_feeds = feeds.enabled
      return true unless enabled_feeds.exists?

      feed_ids = enabled_feeds.pluck(:id)
      disabled_count = enabled_feeds.update_all(state: :disabled)
      create_validation_failed_event(event_type: event_type, feed_ids: feed_ids, disabled_count: disabled_count)
    end

    true
  end

  private

  def schedule_validation_timeout(run_id, started_at)
    AccessTokenValidationTimeoutJob.set(wait_until: started_at + VALIDATION_TIMEOUT).perform_later(self, run_id)
  end

  def create_validation_failed_event(event_type:, feed_ids:, disabled_count:)
    Event.create!(
      type: event_type,
      user: user,
      subject: self,
      level: :warning,
      metadata: { disabled_feed_ids: feed_ids, disabled_count: disabled_count }
    )
  end

  def generate_default_name
    self.name = "Token #{next_available_token_number}"
  end

  def next_available_token_number
    counter = 1

    loop do
      candidate_name = "Token #{counter}"
      break unless user.access_tokens.where(name: candidate_name).where.not(id: id).exists?
      counter += 1
    end

    counter
  end
end
