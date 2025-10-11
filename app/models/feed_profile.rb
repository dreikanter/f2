# Feed profile configuration that defines how feeds are processed
# Each profile specifies a loader, processor, and normalizer combination
class FeedProfile
  PROFILES = {
    "rss" => { loader: "http", processor: "rss", normalizer: "rss" },
    "xkcd" => { loader: "http", processor: "rss", normalizer: "xkcd" }
  }.freeze

  attr_reader :key

  # @param key [String] the profile key (e.g., "rss", "xkcd")
  def initialize(key)
    @key = key
    @config = PROFILES[key]
  end

  # Returns all available profile keys
  # @return [Array<String>] list of profile keys
  def self.all
    PROFILES.keys
  end

  # Checks if a profile key exists
  # @param key [String] the profile key to check
  # @return [Boolean] true if the profile exists
  def self.exists?(key)
    PROFILES.key?(key)
  end

  # Returns the configuration for a given feed
  # @param feed [Feed] the feed to get configuration for
  # @return [Hash] configuration with resolved classes
  def self.for(feed)
    return nil if feed.feed_profile_key.blank?

    profile = new(feed.feed_profile_key)
    {
      loader_class: profile.loader_class,
      processor_class: profile.processor_class,
      normalizer_class: profile.normalizer_class
    }
  end

  # Returns true if the profile is valid (exists in PROFILES)
  # @return [Boolean]
  def valid?
    @config.present?
  end

  # Resolves and returns the loader class for this profile
  # @return [Class] the loader class
  def loader_class
    return nil unless valid?
    ClassResolver.resolve("Loader", @config[:loader])
  end

  # Resolves and returns the processor class for this profile
  # @return [Class] the processor class
  def processor_class
    return nil unless valid?
    ClassResolver.resolve("Processor", @config[:processor])
  end

  # Resolves and returns the normalizer class for this profile
  # @return [Class] the normalizer class
  def normalizer_class
    return nil unless valid?
    ClassResolver.resolve("Normalizer", @config[:normalizer])
  end
end
