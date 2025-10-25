class User < ApplicationRecord
  PASSWORD_RESET_TTL = 15.minutes
  EMAIL_CONFIRMATION_TTL = 24.hours
  PASSWORD_MIN_LENGTH = 10
  PASSWORD_MAX_LENGTH = 72

  has_secure_password

  has_many :sessions, dependent: :destroy
  has_many :feeds, dependent: :destroy
  has_many :feed_previews, dependent: :destroy
  has_many :permissions, dependent: :destroy
  has_many :access_tokens, dependent: :destroy
  has_many :created_invites, class_name: "Invite", foreign_key: :created_by_user_id, dependent: :destroy

  has_one :invite, class_name: "Invite", foreign_key: :invited_user_id, dependent: :nullify
  has_one :invited_by_user, through: :invite, source: :created_by_user

  enum :state, { inactive: 0, onboarding: 1, active: 2, suspended: 3 }, default: :inactive

  validates :email_address, presence: true
  validates :password, length: { minimum: PASSWORD_MIN_LENGTH, maximum: PASSWORD_MAX_LENGTH }, allow_nil: true
  validates :available_invites, numericality: { greater_than_or_equal_to: 0 }
  validate :both_emails_are_globally_unique

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :unconfirmed_email, with: ->(e) { e&.strip&.downcase }

  before_save :set_password_updated_at, if: :will_save_change_to_password_digest?

  generates_token_for :password_reset, expires_in: PASSWORD_RESET_TTL do
    password_salt&.last(10)
  end

  generates_token_for :initial_email_confirmation, expires_in: EMAIL_CONFIRMATION_TTL do
    email_address
  end

  generates_token_for :change_email_confirmation, expires_in: EMAIL_CONFIRMATION_TTL do
    unconfirmed_email
  end

  def permission?(permission_name)
    permissions.exists?(name: permission_name)
  end

  def admin?
    permission?("admin")
  end

  def suspend!
    update!(state: :suspended, suspended_at: Time.current)
  end

  def unsuspend!
    update!(state: :active, suspended_at: nil)
  end

  # Returns the count of all feeds created by this user
  # @return [Integer] total number of feeds
  def total_feeds_count
    feeds.count
  end

  # Returns the count of all imported posts across all user's feeds
  # @return [Integer] total number of imported posts
  def total_imported_posts_count
    imported_posts.count
  end

  # Returns the count of published posts across all user's feeds
  # @return [Integer] total number of published posts
  def total_published_posts_count
    published_posts.count
  end

  # Returns the timestamp of the most recently published post across all user's feeds
  # @return [Time, nil] most recent publication timestamp or nil if no published posts
  def most_recent_post_published_at
    published_posts.maximum(:published_at)
  end

  # Returns the average number of posts per day for the last week across all user's feeds
  # @return [Float] average posts per day (0.0 if no posts)
  def average_posts_per_day_last_week
    start_date = 1.week.ago.beginning_of_day
    end_date = Time.current.end_of_day
    count = imported_posts.where(published_at: start_date..end_date).count
    (count / 7.0).round(1)
  end

  def update_password!(new_password)
    update!(password: new_password, password_confirmation: new_password)
  end

  private

  def both_emails_are_globally_unique
    errors.add(:base, "email is already taken") if other_records_with_same_email?
  end

  def other_records_with_same_email?
    emails = [email_address, unconfirmed_email].compact_blank
    return false if emails.blank?

    scope = User.where.not(id: id)
    scope.where(email_address: emails).or(scope.where(unconfirmed_email: emails)).exists?
  end

  def published_posts
    imported_posts.where(posts: { status: :published })
  end

  def imported_posts
    Post.joins(:feed).where(feeds: { user_id: id })
  end

  def set_password_updated_at
    self.password_updated_at = Time.current
  end
end
