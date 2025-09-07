class AccessToken < ApplicationRecord
  MAX_TOKENS_PER_USER = 20

  belongs_to :user

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :token, presence: true, on: :create
  validate :user_tokens_limit

  before_create :generate_token_digest

  enum :status, { active: 0, inactive: 1 }

  attr_accessor :token

  def authenticate(token_to_check)
    return false unless active?

    BCrypt::Password.new(token_digest) == token_to_check
  end

  def deactivate!
    update!(status: :inactive)
  end

  def touch_last_used!
    update!(last_used_at: Time.current)
  end

  private

  def generate_token_digest
    return unless token.present?

    self.token_digest = BCrypt::Password.create(token)
  end

  def user_tokens_limit
    return unless user&.persisted?
    return unless user.access_tokens.where.not(id: id).count >= MAX_TOKENS_PER_USER

    errors.add(:user, "cannot have more than #{MAX_TOKENS_PER_USER} access tokens")
  end
end
