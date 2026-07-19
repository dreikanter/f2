# Secret capability-URL token of a webhook feed (spec 006 §2). Deterministic
# encryption keeps the token queryable and re-displayable; a separate table
# keeps it out of feed.attributes, which error reporting attaches verbatim.
class WebhookEndpoint < ApplicationRecord
  TOKEN_BYTES = 32

  belongs_to :feed

  encrypts :encrypted_token, deterministic: true

  validates :feed_id, uniqueness: true
  validates :encrypted_token, presence: true, uniqueness: true

  before_validation(on: :create) { self.encrypted_token ||= self.class.generate_token }
  after_destroy :forget_rate_limit

  def self.generate_token
    SecureRandom.urlsafe_base64(TOKEN_BYTES)
  end

  def rate_limit_subject
    "webhook_endpoint:#{id}"
  end

  # The remedy for a leaked URL: the old one stops resolving immediately.
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
