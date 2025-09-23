class FeedProfile < ApplicationRecord
  belongs_to :user
  has_many :feeds, dependent: :nullify
  has_many :feed_previews, dependent: :destroy

  validates :name, presence: true, uniqueness: true,
            length: { maximum: 100 },
            format: { with: /\A[a-z\d\-_]+\z/, message: "must contain only lowercase letters, numbers, hyphens, and underscores" }

  validates :loader, presence: true
  validates :processor, presence: true
  validates :normalizer, presence: true

  normalizes :name, with: ->(name) { name.to_s.strip.downcase }

  before_destroy :deactivate_related_feeds

  # Resolves and returns the loader class for this profile
  # @return [Class] the loader class
  def loader_class
    ClassResolver.resolve("Loader", loader)
  end

  # Resolves and returns the processor class for this profile
  # @return [Class] the processor class
  def processor_class
    ClassResolver.resolve("Processor", processor)
  end

  # Resolves and returns the normalizer class for this profile
  # @return [Class] the normalizer class
  def normalizer_class
    ClassResolver.resolve("Normalizer", normalizer)
  end

  # Creates and returns a loader instance for the given feed
  # @param feed [Feed] the feed to create loader for
  # @return [Loader::Base] loader instance
  def loader_instance(feed)
    loader_class.new(feed)
  end

  # Creates and returns a processor instance for the given feed
  # @param feed [Feed] the feed to create processor for
  # @param raw_data [String] raw feed data to process
  # @return [Processor::Base] processor instance
  def processor_instance(feed, raw_data)
    processor_class.new(feed, raw_data)
  end

  # Creates and returns a normalizer instance for the given feed entry
  # @param feed_entry [FeedEntry] the feed entry to normalize
  # @return [Normalizer::Base] normalizer instance
  def normalizer_instance(feed_entry)
    normalizer_class.new(feed_entry)
  end

  private

  def deactivate_related_feeds
    feeds.enabled.update_all(state: :disabled)
  end
end
