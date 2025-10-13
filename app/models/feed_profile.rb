# Feed profile configuration that defines how feeds are processed.
#
class FeedProfile
  PROFILES = {
    "rss" => {
      loader: "Loader::HttpLoader",
      processor: "Processor::RssProcessor",
      normalizer: "Normalizer::RssNormalizer",
      title_extractor: "TitleExtractor::RssTitleExtractor"
    },
    "xkcd" => {
      loader: "Loader::HttpLoader",
      processor: "Processor::RssProcessor",
      normalizer: "Normalizer::XkcdNormalizer",
      title_extractor: "TitleExtractor::RssTitleExtractor"
    }
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
    class_name = PROFILES.dig(key, :loader)
    raise ArgumentError, "Profile '#{key}' not found" unless class_name

    class_name.constantize
  end

  # Resolves and returns the processor class for a given profile key
  # @param key [String] the profile key
  # @return [Class] the processor class
  def self.processor_class_for(key)
    class_name = PROFILES.dig(key, :processor)
    raise ArgumentError, "Profile '#{key}' not found" unless class_name

    class_name.constantize
  end

  # Resolves and returns the normalizer class for a given profile key
  # @param key [String] the profile key
  # @return [Class] the normalizer class
  def self.normalizer_class_for(key)
    class_name = PROFILES.dig(key, :normalizer)
    raise ArgumentError, "Profile '#{key}' not found" unless class_name

    class_name.constantize
  end

  # Resolves and returns the title extractor class for a given profile key
  # @param key [String] the profile key
  # @return [Class] the title extractor class
  def self.title_extractor_class_for(key)
    class_name = PROFILES.dig(key, :title_extractor)
    raise ArgumentError, "Profile '#{key}' not found" unless class_name

    class_name.constantize
  end
end
