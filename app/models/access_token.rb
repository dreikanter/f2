class AccessToken < ApplicationRecord
  belongs_to :user
  has_many :feeds
  has_one :access_token_detail, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :token, presence: true, on: :create
  validates :host, presence: true, inclusion: { in: -> { FREEFEED_HOSTS.values.map { |config| config[:url] } }, message: "must be a known FreeFeed host" }

  enum :status, { pending: 0, validating: 1, active: 2, inactive: 3 }

  before_validation :generate_default_name, if: -> { name.blank? }
  before_destroy :disable_associated_feeds

  encrypts :encrypted_token

  attr_accessor :token

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
    update!(status: :validating)
    TokenValidationJob.perform_later(self)
  end

  def token_value
    encrypted_token
  end


  def touch_last_used!
    touch(:last_used_at)
  end

  def build_client
    FreefeedClient.new(host: host, token: token_value)
  end

  def username_with_host
    return nil unless owner.present?

    "#{owner}@#{host_domain}"
  end

  def host_domain
    FREEFEED_HOSTS.values.find { |config| config[:url] == host }.fetch(:domain)
  end

  def disable_associated_feeds
    feeds.enabled.update_all(state: :disabled, access_token_id: nil)
  end

  private

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
