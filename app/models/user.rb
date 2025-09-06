class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :feeds, dependent: :destroy
  has_many :permissions, dependent: :destroy
  has_many :access_tokens, dependent: :destroy

  validates :email_address, presence: true, uniqueness: true
  validate :max_access_tokens_limit
  normalizes :email_address, with: ->(e) { e.strip.downcase }

  generates_token_for :password_reset, expires_in: 15.minutes do
    password_salt&.last(10)
  end

  generates_token_for :email_change, expires_in: 15.minutes do
    email_address
  end

  private

  def max_access_tokens_limit
    return unless persisted? && access_tokens.size >= 20

    errors.add(:access_tokens, "cannot exceed 20 tokens per user")
  end
end
