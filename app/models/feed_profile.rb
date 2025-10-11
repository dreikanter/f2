# Feed profile configuration that defines how feeds are processed.
#
class FeedProfile
  PROFILES = {
    "rss" => { loader: "http", processor: "rss", normalizer: "rss" },
    "xkcd" => { loader: "http", processor: "rss", normalizer: "xkcd" }
  }.freeze

  attr_reader :key

  # @param key [String] the profile key (e.g., "rss", "xkcd")
  # @raise [ArgumentError] if the profile key doesn't exist
  def initialize(key)
    @key = key
    @config = PROFILES.fetch(key) { raise ArgumentError, "Unknown feed profile: #{key}" }
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

  # Returns the configuration hash for a given key
  # @param key [String] the profile key
  # @return [Hash, nil] configuration hash with loader, processor, normalizer keys
  def self.for(key)
    PROFILES[key]
  end

  # Resolves and returns the loader class for this profile
  # @return [Class] the loader class
  def loader_class
    ClassResolver.resolve("Loader", @config[:loader])
  end

  # Resolves and returns the processor class for this profile
  # @return [Class] the processor class
  def processor_class
    ClassResolver.resolve("Processor", @config[:processor])
  end

  # Resolves and returns the normalizer class for this profile
  # @return [Class] the normalizer class
  def normalizer_class
    ClassResolver.resolve("Normalizer", @config[:normalizer])
  end
end
