class Event < ApplicationRecord
  self.inheritance_column = nil

  belongs_to :user, optional: true
  belongs_to :subject, polymorphic: true, optional: true

  has_many :event_references, dependent: :delete_all

  enum :level, { debug: 0, info: 1, warning: 2, error: 3 }

  validates :type, presence: true
  validates :level, inclusion: { in: levels.keys }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_subject, ->(subject) { where(subject: subject) }
  scope :expired, -> { where("expires_at IS NOT NULL AND expires_at < ?", Time.current) }
  scope :not_expired, -> { where("expires_at IS NULL OR expires_at >= ?", Time.current) }
  scope :user_relevant, -> { where.not(level: :debug).not_expired }

  def alert_variant
    level == "debug" ? :info : level.to_sym
  end

  # Records this event points at, with deleted ones dropped. Distinct from
  # #event_references, which are the join rows themselves.
  def references
    event_references.referenced_records
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def expires_in(duration)
    update!(expires_at: duration.from_now)
    self
  end

  def self.purge_expired
    ids = expired.ids
    EventReference.where(event_id: ids).delete_all
    where(id: ids).delete_all
  end
end
