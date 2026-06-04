class Permission < ApplicationRecord
  belongs_to :user

  ADMIN = "admin"
  DEV   = "dev"

  AVAILABLE_PERMISSIONS = [ADMIN, DEV].freeze

  LABELS = {
    ADMIN => { name: "Admin", description: "Full admin panel access and user management." },
    DEV   => { name: "Dev", description: "Developer tools and experimental features." }
  }.freeze

  validates :name, presence: true, inclusion: { in: AVAILABLE_PERMISSIONS }
  validates :user_id, uniqueness: { scope: :name }
end
