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

  def user_info
    (data && data["user_info"]) || {}
  end

  def managed_groups
    (data && data["managed_groups"]) || []
  end
end
