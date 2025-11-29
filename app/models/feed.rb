class Feed < ApplicationRecord
  NAME_MAX_LENGTH = 40
  DESCRIPTION_MAX_LENGTH = 100
  TARGET_GROUP_PATTERN = /\A[a-z0-9_-]+\z/.freeze
  TARGET_GROUP_MAX_LENGTH = 80
  IDENTIFICATION_POLLING_INTERVAL_MS = 2000

  SUPPORTED_METRICS = %i[
    posts_count
    invalid_posts_count
  ].freeze

  # Timezone for all cron expression evaluation
  # Must match config.time_zone in config/application.rb
  FEED_CRON_TIMEZONE = "UTC".freeze

  SCHEDULE_INTERVALS = {
    "10m" => { cron: "*/10 * * * *", display: "10 minutes" },
    "20m" => { cron: "*/20 * * * *", display: "20 minutes" },
    "30m" => { cron: "*/30 * * * *", display: "30 minutes" },
    "1h" => { cron: "0 * * * *", display: "1 hour" },
    "2h" => { cron: "0 */2 * * *", display: "2 hours" },
    "6h" => { cron: "0 */6 * * *", display: "6 hours" },
    "12h" => { cron: "0 */12 * * *", display: "12 hours" },
    "1d" => { cron: "0 0 * * *", display: "1 day" },
    "2d" => { cron: "0 0 */2 * *", display: "2 days" }
  }.freeze

  belongs_to :user
  belongs_to :access_token, optional: true

  has_one :feed_schedule, dependent: :destroy

  has_many :events, as: :subject, dependent: :destroy
  has_many :feed_entries, dependent: :destroy
  has_many :feed_metrics, dependent: :destroy
  has_many :posts, dependent: :destroy

  enum :state, { disabled: 0, enabled: 1 }, default: :disabled

  after_update :create_schedule_on_enable

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

  validates :cron_expression, presence: true, if: :enabled?
  validates :feed_profile_key, presence: true
  validates :feed_profile_key, inclusion: { in: ->(_) { FeedProfile.all } }, if: -> { feed_profile_key.present? }

  normalizes :name, with: ->(name) { name.to_s.strip }
  normalizes :url, with: ->(url) { url.to_s.strip }
  normalizes :cron_expression, with: ->(cron) { cron.to_s.strip }
  normalizes :description, with: ->(desc) { desc.to_s.gsub(/\s+/, " ").strip }
  normalizes :target_group, with: ->(group) { group.present? ? group.to_s.strip.downcase : nil }

  validate :cron_expression_is_valid
  validates :access_token, presence: true, if: :enabled?
  validates :target_group, presence: true, if: :enabled?

  validates :target_group,
            length: { maximum: TARGET_GROUP_MAX_LENGTH },
            format: {
              with: TARGET_GROUP_PATTERN,
              message: "must contain only lowercase letters, numbers, underscores and dashes"
            },
            allow_blank: true

  scope :due, -> {
    left_joins(:feed_schedule)
      .where("feed_schedules.next_run_at <= ? OR feed_schedules.id IS NULL", Time.current)
      .where(state: :enabled)
  }

  def self.schedule_intervals_for_select
    SCHEDULE_INTERVALS.map { |key, config| [config[:display], key] }
  end

  def schedule_interval
    SCHEDULE_INTERVALS.find { |_key, config| config[:cron] == cron_expression }&.first
  end

  def schedule_interval=(key)
    self.cron_expression = SCHEDULE_INTERVALS.dig(key, :cron)
  end

  def schedule_display
    SCHEDULE_INTERVALS.dig(schedule_interval, :display) || cron_expression
  end

  def feed_profile_present?
    feed_profile_key.present? && FeedProfile.exists?(feed_profile_key)
  end

  # Resolves and returns the loader class for this feed
  # @return [Class] the loader class
  def loader_class
    FeedProfile.loader_class_for(feed_profile_key)
  end

  # Resolves and returns the processor class for this feed
  # @return [Class] the processor class
  def processor_class
    FeedProfile.processor_class_for(feed_profile_key)
  end

  # Resolves and returns the normalizer class for this feed
  # @return [Class] the normalizer class
  def normalizer_class
    FeedProfile.normalizer_class_for(feed_profile_key)
  end

  def can_be_enabled?
    access_token&.active? && target_group.present? && feed_profile_present? && cron_expression.present?
  end

  def can_be_previewed?
    url.present? && feed_profile_present?
  end

  # Creates and returns a loader instance for this feed
  # @return [Loader::Base] loader instance
  def loader_instance
    loader_class.new(self)
  end

  # Creates and returns a processor instance for this feed
  # @param raw_data [String] raw feed data to process
  # @return [Processor::Base] processor instance
  def processor_instance(raw_data)
    processor_class.new(self, raw_data)
  end

  # Creates and returns a normalizer instance for the given feed entry
  # @param feed_entry [FeedEntry] the feed entry to normalize
  # @return [Normalizer::Base] normalizer instance
  def normalizer_instance(feed_entry)
    normalizer_class.new(feed_entry)
  end

  # Returns the number of posts per day for the specified date range
  # @param start_date [Date] start date of the range
  # @param end_date [Date] end date of the range (inclusive)
  # @return [Hash] hash with dates as keys and post counts as values
  def posts_per_day(start_date, end_date)
    posts.where(published_at: start_date.beginning_of_day..end_date.end_of_day)
         .group("DATE(published_at)")
         .count
  end

  # Returns the date when the feed was last refreshed
  # @return [Time, nil] last refresh time or nil if never refreshed
  def last_refreshed_at
    feed_entries.maximum(:created_at)
  end

  # Returns the date of the most recent imported post
  # @return [Time, nil] most recent post date or nil if no posts
  def most_recent_post_date
    posts.maximum(:published_at)
  end

  # Returns metrics for a date range, filling gaps with zeros
  # @param start_date [Date] start date of the range
  # @param end_date [Date] end date of the range (inclusive)
  # @param metric [Symbol] the metric to retrieve (:posts_count or :invalid_posts_count)
  # @return [Array<Hash>] array of hashes with :date and metric value
  def metrics_for_date_range(start_date, end_date, metric: :posts_count)
    raise ArgumentError, "Unsupported metric: #{metric}" unless SUPPORTED_METRICS.include?(metric)

    sql = <<-SQL.squish
      SELECT
        d.date::date,
        COALESCE(fm.#{metric}, 0) as #{metric}
      FROM generate_series(
        $1::date,
        $2::date,
        '1 day'::interval
      ) AS d(date)
      LEFT JOIN feed_metrics fm
        ON fm.date = d.date::date
        AND fm.feed_id = $3
      ORDER BY d.date
    SQL

    ActiveRecord::Base.connection.exec_query(
      sql,
      "SQL",
      [start_date.to_s, end_date.to_s, id]
    ).to_a
  end

  # Creates a feed schedule with initial timestamps
  # @return [FeedSchedule] the created schedule
  def create_initial_schedule!
    create_feed_schedule!(
      next_run_at: Time.current,
      last_run_at: Time.current
    )
  end

  private

  def cron_expression_is_valid
    return if cron_expression.blank?

    parsed_cron = Fugit.parse(cron_expression)
    errors.add(:cron_expression, "is not a valid cron expression") unless parsed_cron
  end

  def create_schedule_on_enable
    return unless saved_change_to_state?
    return unless enabled?
    return if feed_schedule.present?

    create_initial_schedule!
  end
end
