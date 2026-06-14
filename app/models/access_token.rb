class AccessToken < ApplicationRecord
  belongs_to :user
  has_many :feeds
  has_one :access_token_detail, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :token, presence: true, on: :create
  validates :host, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid HTTP or HTTPS URL" }

  enum :status, { pending: 0, validating: 1, active: 2, inactive: 3 }

  before_validation :generate_default_name, if: -> { name.blank? }
  before_destroy :disable_associated_feeds
  after_destroy :forget_rate_limit_state

  encrypts :encrypted_token

  attr_accessor :token

  # A user can create access token record associated with a known
  # FreeFeed instances only (see Settings::AccessTokensController).
  # Though the model allows to define any valid host URL.
  FREEFEED_HOSTS = {
    production: {
      url: "https://freefeed.net",
      display_name: "freefeed.net (main)",
      domain: "freefeed.net",
      token_url: "https://freefeed.net/settings/app-tokens/create?scopes=read-my-info%20manage-posts"
    },
    staging: {
      url: "https://candy.freefeed.net",
      display_name: "candy.freefeed.net (staging)",
      domain: "candy.freefeed.net",
      token_url: "https://candy.freefeed.net/settings/app-tokens/create?scopes=read-my-info%20manage-posts"
    },
    beta: {
      url: "https://beta.freefeed.net",
      display_name: "beta.freefeed.net (beta)",
      domain: "beta.freefeed.net",
      token_url: "https://beta.freefeed.net/settings/app-tokens/create?scopes=read-my-info%20manage-posts"
    }
  }.freeze

  def self.host_options_for_select
    FREEFEED_HOSTS.map { |_key, config| [config[:display_name], config[:url]] }
  end

  def self.build_with_token(attributes = {})
    defaults = {
      status: :pending,
      encrypted_token: attributes[:token],
      host: FREEFEED_HOSTS[:production][:url]
    }

    new(defaults.merge(attributes))
  end

  def validate_token_async
    validating!
    TokenValidationJob.perform_later(self)
  end

  def build_client
    FreefeedClient.new(host: host, token: encrypted_token, rate_limit_subject: rate_limit_subject)
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

  def display_name
    owner = access_token_detail&.user_info&.dig("username") || name
    "#{host_domain} - #{owner}"
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

  def disable_token_and_feeds
    with_lock do
      inactive!

      enabled_feeds = feeds.enabled
      return unless enabled_feeds.exists?

      feed_ids = enabled_feeds.pluck(:id)
      disabled_count = enabled_feeds.update_all(state: :disabled)
      create_validation_failed_event(feed_ids: feed_ids, disabled_count: disabled_count)
    end
  end

  private

  def create_validation_failed_event(feed_ids:, disabled_count:)
    Event.create!(
      type: "access_token_validation_failed",
      user: user,
      subject: self,
      level: :warning,
      message: "",
      metadata: { disabled_feed_ids: feed_ids, disabled_count: disabled_count }
    )
  end

  def generate_default_name
    self.name = "Token #{next_available_token_number}"
  end

  # TBD: Optimize this the token management flow is when stabilized
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
