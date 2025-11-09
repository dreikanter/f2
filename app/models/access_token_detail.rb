class AccessTokenDetail < ApplicationRecord
  belongs_to :access_token

  validates :data, presence: true

  def user_info
    (data && data["user_info"]) || {}
  end

  def managed_groups
    (data && data["managed_groups"]) || []
  end
end
