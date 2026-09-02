class Session < ApplicationRecord
  INACTIVITY_TIMEOUT = 30.days

  belongs_to :user

  scope :active, -> { where("COALESCE(last_seen_at, created_at) >= ?", INACTIVITY_TIMEOUT.ago) }
  scope :established, -> { where.not(last_seen_at: nil) }

  def self.find_active(id)
    active.find_by(id: id) if id.present?
  end
end
