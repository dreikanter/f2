class AccessToken < ApplicationRecord
  MAX_TOKENS_PER_USER = 20

  belongs_to :user

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :token, presence: true, on: :create
  validate :user_tokens_limit

  enum :status, { pending: 0, active: 1, inactive: 2 }

  attr_accessor :token

  def self.build_with_token(attributes = {})
    token_value = attributes.delete(:token)
    instance = new(attributes.merge(status: :pending))

    if token_value.present?
      instance.token = token_value
      instance.token_digest = BCrypt::Password.create(token_value)
    end

    instance
  end

  def validate_token_async
    TokenValidationJob.perform_later(self)
  end

  def mark_as_active!(owner_username = nil)
    update!(status: :active, owner: owner_username)
  end

  def mark_as_inactive!
    update!(status: :inactive)
  end

  def touch_last_used!
    touch(:last_used_at)
  end

  private

  def user_tokens_limit
    return unless user&.persisted?
    return unless user.access_tokens.where.not(id: id).count >= MAX_TOKENS_PER_USER

    errors.add(:user, "cannot have more than #{MAX_TOKENS_PER_USER} access tokens")
  end
end
