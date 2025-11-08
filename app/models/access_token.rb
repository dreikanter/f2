class AccessToken < ApplicationRecord
  belongs_to :user
  has_many :feeds
  has_one :access_token_detail, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :token, presence: true, on: :create
  validates :host, presence: true, format: { with: /\Ahttps?:\/\/[^\s]+\z/, message: "must be a valid HTTP(S) URL" }

  enum :status, { pending: 0, validating: 1, active: 2, inactive: 3 }

  before_validation :set_default_name, on: :create
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

  private

  def set_default_name
    return if name.present?

    host_config = FREEFEED_HOSTS.values.find { |config| config[:url] == host }
    domain = host_config ? host_config[:domain] : URI.parse(host).host

    self.name = "New token for #{domain}"
  end

  def disable_associated_feeds
    feeds.update_all(state: :disabled, access_token_id: nil)
  end
end
