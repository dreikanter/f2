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

  def self.generate_token
    SecureRandom.urlsafe_base64(TOKEN_BYTES)
  end

  # The remedy for a leaked URL: the old one stops resolving immediately.
  def rotate!
    update!(encrypted_token: self.class.generate_token)
  end
end
