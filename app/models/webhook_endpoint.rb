# The ingress identity of a push feed: a secret capability-URL token
# (spec 006 §2). Deterministic encryption keeps the token queryable through
# the unique index and re-displayable on the feed page, while a separate
# table keeps secret material out of feed.attributes (attached verbatim to
# error-tracking context).
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

  # Replaces the token in place — the remedy for a leaked URL. The old URL
  # stops resolving the moment this commits.
  def rotate!
    update!(encrypted_token: self.class.generate_token)
  end
end
