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

  # Posts this event references that still exist. References intentionally
  # outlive the posts they point at, so deleted posts simply drop out here.
  def imported_posts
    Post.where(id: event_references.where(reference_type: "Post").select(:reference_id))
        .order(published_at: :desc)
  end

  # Count of referenced posts, including ones the user later deleted. Uses the
  # loaded association when preloaded to stay cheap inside event lists.
  def imported_posts_count
    event_references.count { |reference| reference.reference_type == "Post" }
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
