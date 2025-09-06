class AccessToken < ApplicationRecord
  belongs_to :user

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validate :user_tokens_limit

  before_create :generate_token_digest
  after_initialize :set_defaults

  scope :active, -> { where(is_active: true) }

  attr_accessor :token

  def generate_token
    self.token = SecureRandom.base64(195) # ~260 characters
    self.token_digest = BCrypt::Password.create(token)
  end

  def authenticate(token_to_check)
    return false unless is_active?

    BCrypt::Password.new(token_digest) == token_to_check
  end

  def deactivate!
    update!(is_active: false)
  end

  def touch_last_used!
    update!(last_used_at: Time.current)
  end

  private

  def generate_token_digest
    generate_token if token_digest.blank?
  end

  def set_defaults
    self.is_active = true if is_active.nil?
  end

  def user_tokens_limit
    return unless user&.persisted?
    return unless user.access_tokens.where.not(id: id).count >= 20

    errors.add(:user, "cannot have more than 20 access tokens")
  end
end
