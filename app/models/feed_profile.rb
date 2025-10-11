# Feed profile configuration that defines how feeds are processed.
#
class FeedProfile
  PROFILES = {
    "rss" => { loader: "http", processor: "rss", normalizer: "rss" },
    "xkcd" => { loader: "http", processor: "rss", normalizer: "xkcd" }
  }.freeze

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

  # Resolves and returns the loader class for a given profile key
  # @param key [String] the profile key
  # @return [Class, nil] the loader class or nil if key is invalid
  def self.loader_class_for(key)
    config = PROFILES[key]
    return nil unless config
    ClassResolver.resolve("Loader", config[:loader])
  end

  # Resolves and returns the processor class for a given profile key
  # @param key [String] the profile key
  # @return [Class, nil] the processor class or nil if key is invalid
  def self.processor_class_for(key)
    config = PROFILES[key]
    return nil unless config
    ClassResolver.resolve("Processor", config[:processor])
  end

  # Resolves and returns the normalizer class for a given profile key
  # @param key [String] the profile key
  # @return [Class, nil] the normalizer class or nil if key is invalid
  def self.normalizer_class_for(key)
    config = PROFILES[key]
    return nil unless config
    ClassResolver.resolve("Normalizer", config[:normalizer])
  end
end
