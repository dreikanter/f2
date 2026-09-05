class Session < ApplicationRecord
  INACTIVITY_TIMEOUT = 30.days

  belongs_to :user

  before_validation :initialize_last_seen_at, on: :create
  after_save :record_user_activity, if: :saved_change_to_last_seen_at?

  validates :last_seen_at, presence: true

  scope :active, -> { where(last_seen_at: INACTIVITY_TIMEOUT.ago..) }
  scope :expired, -> { where(last_seen_at: ...INACTIVITY_TIMEOUT.ago) }

  def self.find_active(id)
    active.find_by(id: id) if id.present?
  end

  private

  def initialize_last_seen_at
    self.last_seen_at ||= Time.current
  end

  def record_user_activity
    # Concurrent activity from another session must never move Last Seen back.
    User.where(id: user_id).where("last_seen_at IS NULL OR last_seen_at < ?", last_seen_at)
      .update_all(last_seen_at: last_seen_at)
  end
end
