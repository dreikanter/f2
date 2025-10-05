class AccessToken < ApplicationRecord
  belongs_to :user
  has_many :feeds

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :token, presence: true, on: :create
  validates :host, presence: true, format: { with: /\Ahttps?:\/\/[^\s]+\z/, message: "must be a valid HTTP(S) URL" }

  enum :status, { pending: 0, validating: 1, active: 2, inactive: 3 }

  before_destroy :disable_associated_feeds

  encrypts :encrypted_token

  attr_accessor :token

  FREEFEED_HOSTS = {
    "production" => "https://freefeed.net",
    "staging" => "https://candy.freefeed.net",
    "beta" => "https://beta.freefeed.net"
  }.freeze

  def self.build_with_token(attributes = {})
    defaults = {
      status: :pending,
      encrypted_token: attributes[:token],
      host: FREEFEED_HOSTS["production"]
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

  def disable_associated_feeds
    feeds.update_all(state: :disabled, access_token_id: nil)
  end
end
