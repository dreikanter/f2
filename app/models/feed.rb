class Feed < ApplicationRecord
  NAME_PATTERN = /\A[a-z0-9_-]+\z/.freeze
  NAME_MAX_LENGTH = 40
  DESCRIPTION_MAX_LENGTH = 100

  belongs_to :user
  belongs_to :access_token, optional: true
  has_one :feed_schedule, dependent: :destroy
  has_many :feed_entries, dependent: :destroy

  enum :state, { enabled: 0, paused: 1, disabled: 2 }

  validates :name,
            presence: true,
            uniqueness: { scope: :user_id },
            length: { maximum: NAME_MAX_LENGTH }

  validates :url,
            presence: true,
            format: {
              with: URI::DEFAULT_PARSER.make_regexp(%w[http https]),
              message: "must be a valid HTTP or HTTPS URL"
            }

  validates :cron_expression, presence: true
  validates :loader, presence: true
  validates :processor, presence: true
  validates :normalizer, presence: true

  normalizes :name, with: ->(name) { name.to_s.strip }
  normalizes :url, with: ->(url) { url.to_s.strip }
  normalizes :cron_expression, with: ->(cron) { cron.to_s.strip }
  normalizes :description, with: ->(desc) { desc.to_s.gsub(/\s+/, " ").strip }

  validate :cron_expression_is_valid
  validates :access_token, presence: true, if: :enabled?

  scope :due, -> {
    left_joins(:feed_schedule)
      .where("feed_schedules.next_run_at <= ? OR feed_schedules.id IS NULL", Time.current)
      .where(state: :enabled)
  }

  after_initialize :set_default_state, if: :new_record?
  before_save :auto_disable_without_active_token

  private

  def set_default_state
    self.state ||= :disabled
  end

  def auto_disable_without_active_token
    return unless enabled?
    return if access_token&.active?

    self.state = :disabled
  end

  def cron_expression_is_valid
    return if cron_expression.blank?

    parsed_cron = Fugit.parse(cron_expression)
    errors.add(:cron_expression, "is not a valid cron expression") unless parsed_cron
  end
end
