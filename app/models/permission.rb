class Permission < ApplicationRecord
  belongs_to :user

  ADMIN = "admin"
  DEV   = "dev"

  AVAILABLE_PERMISSIONS = [ADMIN, DEV].freeze

  validates :name, presence: true, inclusion: { in: AVAILABLE_PERMISSIONS }
  validates :user_id, uniqueness: { scope: :name }
end
