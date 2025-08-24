class Feed < ApplicationRecord
  belongs_to :user
  has_one :feed_schedule, dependent: :destroy

  enum :state, { enabled: 0, paused: 1, disabled: 2 }

  validates :name, presence: true, uniqueness: { scope: :user_id }, format: { with: /\A[a-z0-9_-]+\z/, message: "can only contain lowercase letters, numbers, hyphens, and underscores" }
  validates :url, presence: true, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]), message: "must be a valid HTTP or HTTPS URL" }
  validates :cron_expression, presence: true
  validates :loader, presence: true
  validates :processor, presence: true
  validates :normalizer, presence: true

  normalizes :name, with: ->(name) { name&.strip&.downcase }
  normalizes :url, with: ->(url) { url&.strip }
  normalizes :cron_expression, with: ->(cron) { cron&.strip }
  normalizes :description, with: ->(desc) { desc&.gsub(/\r?\n/, " ")&.strip }

  validate :cron_expression_is_valid

  scope :due, -> {
    left_joins(:feed_schedule)
      .where("feed_schedules.next_run_at <= ? OR feed_schedules.id IS NULL", Time.current)
      .where(state: :enabled)
  }

  after_initialize :set_default_state

  private

  def set_default_state
    self.state ||= :enabled if new_record?
  end

  def cron_expression_is_valid
    return if cron_expression.blank?

    parsed_cron = Fugit.parse(cron_expression)
    errors.add(:cron_expression, "is not a valid cron expression") if parsed_cron.nil?
  rescue StandardError => e
    errors.add(:cron_expression, "is not a valid cron expression: #{e.message}")
  end
end
