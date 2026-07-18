class Event < ApplicationRecord
  self.inheritance_column = nil

  # Events without an explicit expiration are kept this long, then purged.
  DEFAULT_RETENTION = 1.month

  belongs_to :user, optional: true
  belongs_to :subject, polymorphic: true, optional: true

  has_many :event_references, dependent: :delete_all
  has_many :incoming_event_references,
           as: :reference,
           class_name: "EventReference",
           dependent: :delete_all

  enum :level, { debug: 0, info: 1, warning: 2, error: 3 }

  validates :type, presence: true
  validates :level, inclusion: { in: levels.keys }

  scope :recent, -> { order(created_at: :desc) }
  # An event is expired once its explicit expiration has passed, or — when it
  # never set one — once it ages past DEFAULT_RETENTION. This is what the purge
  # job deletes.
  scope :expired, -> {
    where("expires_at < :now OR (expires_at IS NULL AND created_at < :cutoff)",
          now: Time.current, cutoff: DEFAULT_RETENTION.ago)
  }
  scope :not_expired, -> {
    where("(expires_at IS NULL OR expires_at >= :now) AND (expires_at IS NOT NULL OR created_at >= :cutoff)",
          now: Time.current, cutoff: DEFAULT_RETENTION.ago)
  }
  scope :user_relevant, -> { where.not(level: :debug).not_expired }

  def alert_variant
    level == "debug" ? :info : level.to_sym
  end

  # Records this event points at, with deleted ones dropped. Distinct from
  # #event_references, which are the join rows themselves.
  def references
    event_references.includes(:reference).filter_map(&:reference)
  end

  def expired?
    return expires_at < Time.current if expires_at.present?

    created_at.present? && created_at < DEFAULT_RETENTION.ago
  end

  def expires_in(duration)
    update!(expires_at: duration.from_now)
    self
  end
end
