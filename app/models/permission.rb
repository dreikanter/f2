class Permission < ApplicationRecord
  belongs_to :user

  AVAILABLE_PERMISSIONS = %w[admin].freeze

  validates :name, presence: true, inclusion: { in: AVAILABLE_PERMISSIONS }
  validates :user_id, uniqueness: { scope: :name }
end
