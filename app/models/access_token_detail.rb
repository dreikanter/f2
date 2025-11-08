class AccessTokenDetail < ApplicationRecord
  TTL = 24.hours

  belongs_to :access_token

  validates :data, presence: true
  validates :expires_at, presence: true

  scope :expired, -> { where(expires_at: ...Time.current) }
  scope :valid, -> { where(expires_at: Time.current..) }

  def expired?
    expires_at < Time.current
  end
end
