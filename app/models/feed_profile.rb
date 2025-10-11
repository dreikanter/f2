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
  # @return [Class] the loader class
  def self.loader_class_for(key)
    ClassResolver.resolve("Loader", PROFILES.dig(key, :loader))
  end

  # Resolves and returns the processor class for a given profile key
  # @param key [String] the profile key
  # @return [Class] the processor class
  def self.processor_class_for(key)
    ClassResolver.resolve("Processor", PROFILES.dig(key, :processor))
  end

  # Resolves and returns the normalizer class for a given profile key
  # @param key [String] the profile key
  # @return [Class] the normalizer class
  def self.normalizer_class_for(key)
    ClassResolver.resolve("Normalizer", PROFILES.dig(key, :normalizer))
  end
end
