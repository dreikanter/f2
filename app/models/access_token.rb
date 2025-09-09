class AccessToken < ApplicationRecord
  MAX_TOKENS_PER_USER = 20

  belongs_to :user

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :token, presence: true, on: :create
  validate :user_tokens_limit

  enum :status, { pending: 0, validating: 1, active: 2, inactive: 3 }

  encrypts :encrypted_token

  attr_accessor :token

  def self.build_with_token(attributes = {})
    defaults = {
      status: :pending,
      encrypted_token: attributes[:token]
    }

    new(attributes.merge(defaults))
  end

  def validate_token_async
    return unless valid?

    update!(status: :validating)
    TokenValidationJob.perform_later(self)
  end

  def token_value
    encrypted_token
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
