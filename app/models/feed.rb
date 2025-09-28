class Feed < ApplicationRecord
  NAME_MAX_LENGTH = 40
  DESCRIPTION_MAX_LENGTH = 100
  TARGET_GROUP_PATTERN = /\A[a-z0-9_-]+\z/.freeze
  TARGET_GROUP_MAX_LENGTH = 80

  belongs_to :user
  belongs_to :access_token, optional: true
  belongs_to :feed_profile, optional: true
  has_one :feed_schedule, dependent: :destroy

  delegate :loader, :processor, :normalizer, :loader_class, :processor_class, :normalizer_class, to: :feed_profile, allow_nil: true
  has_many :feed_entries, dependent: :destroy
  has_many :posts, dependent: :destroy

  enum :state, { disabled: 0, enabled: 1 }, default: :disabled

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
  validates :feed_profile, presence: true

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

  before_validation :auto_disable_without_active_token

  def can_be_enabled?
    access_token&.active? && target_group.present? && feed_profile.present? && cron_expression.present?
  end

  def can_be_previewed?
    url.present? && feed_profile.present?
  end

  def generate_unique_name!
    return if name.present?

    base_name = "Untitled"
    counter = user.feeds.where("name LIKE ?", "#{base_name}%").count + 1
    self.name = "#{base_name} #{counter}"
  end

  # Creates and returns a loader instance for this feed
  # @return [Loader::Base] loader instance
  def loader_instance
    loader_class&.new(self)
  end

  # Creates and returns a processor instance for this feed
  # @param raw_data [String] raw feed data to process
  # @return [Processor::Base] processor instance
  def processor_instance(raw_data)
    processor_class&.new(self, raw_data)
  end

  # Creates and returns a normalizer instance for the given feed entry
  # @param feed_entry [FeedEntry] the feed entry to normalize
  # @return [Normalizer::Base] normalizer instance
  def normalizer_instance(feed_entry)
    normalizer_class&.new(feed_entry)
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

  private

  def auto_disable_without_active_token
    return unless enabled?
    return if can_be_enabled?

    self.state = :disabled
  end

  def cron_expression_is_valid
    return if cron_expression.blank?

    parsed_cron = Fugit.parse(cron_expression)
    errors.add(:cron_expression, "is not a valid cron expression") unless parsed_cron
  end
end
