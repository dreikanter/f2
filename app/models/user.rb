class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :feeds, dependent: :destroy
  has_many :feed_profiles, dependent: :destroy
  has_many :feed_previews, dependent: :destroy
  has_many :permissions, dependent: :destroy
  has_many :access_tokens, dependent: :destroy

  validates :email_address, presence: true, uniqueness: true
  normalizes :email_address, with: ->(e) { e.strip.downcase }

  before_create :set_password_updated_at

  generates_token_for :password_reset, expires_in: 15.minutes do
    password_salt&.last(10)
  end

  generates_token_for :email_change, expires_in: 15.minutes do
    email_address
  end

  def permission?(permission_name)
    permissions.exists?(name: permission_name)
  end

  private

  def set_password_updated_at
    self.password_updated_at = Time.current
  end
end
