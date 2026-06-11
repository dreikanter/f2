class Permission < ApplicationRecord
  belongs_to :user

  ADMIN = "admin"
  DEV   = "dev"

  AVAILABLE_PERMISSIONS = [ADMIN, DEV].freeze

  LABELS = {
    ADMIN => { display_name: "Admin", description: "Full admin panel access and user management." },
    DEV   => { display_name: "Developer Tools", description: "Developer tools and experimental features." }
  }.freeze

  validates :name, presence: true, inclusion: { in: AVAILABLE_PERMISSIONS }
  validates :user_id, uniqueness: { scope: :name }

  def self.display_name(name)
    LABELS.dig(name, :display_name)
  end

  def display_name
    self.class.display_name(name)
  end
end
