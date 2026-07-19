# Authentication credential for one webhook feed. The token is encrypted at
# rest with Rails Active Record Encryption, like the other external credentials
# in the application. Deterministic encryption keeps this high-entropy token
# queryable without exposing a separate feed or endpoint identifier to callers.
class WebhookEndpoint < ApplicationRecord
  TOKEN_BYTES = 32
  TOKEN_PATTERN = /\A[A-Za-z0-9_-]{43}\z/

  belongs_to :feed

  encrypts :encrypted_token, deterministic: true

  validates :feed_id, uniqueness: true
  validates :encrypted_token, presence: true, uniqueness: true

  before_validation(on: :create) { self.encrypted_token ||= self.class.generate_token }
  after_destroy :forget_rate_limit

  def self.generate_token
    SecureRandom.urlsafe_base64(TOKEN_BYTES)
  end

  def self.authenticate(token)
    return unless token.is_a?(String) && TOKEN_PATTERN.match?(token)

    find_by(encrypted_token: token)
  end

  def rate_limit_subject
    "webhook_endpoint:#{id}"
  end

  # Rotation invalidates the old credential immediately.
  def rotate!
    update!(encrypted_token: self.class.generate_token)
  end

  private

  # RateLimit stores one row per subject. The endpoint ID is never reused, so
  # remove its bucket with the endpoint instead of leaking rows indefinitely.
  def forget_rate_limit
    RateLimit.forget(:webhook_ingest, subject: rate_limit_subject)
  end
end
