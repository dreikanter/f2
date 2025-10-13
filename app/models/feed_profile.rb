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

  # Resolves and returns a service class for a given profile key and service type
  # @param key [String] the profile key
  # @param service_type [Symbol] the service type (:loader, :processor, :normalizer, :title_extractor)
  # @return [Class] the service class
  def self.class_for(key, service_type)
    class_name = PROFILES.dig(key, service_type)
    raise ArgumentError, "Profile '#{key}' not found" unless class_name

    class_name.constantize
  end

  # Resolves and returns the loader class for a given profile key
  # @param key [String] the profile key
  # @return [Class] the loader class
  def self.loader_class_for(key)
    class_for(key, :loader)
  end

  # Resolves and returns the processor class for a given profile key
  # @param key [String] the profile key
  # @return [Class] the processor class
  def self.processor_class_for(key)
    class_for(key, :processor)
  end

  # Resolves and returns the normalizer class for a given profile key
  # @param key [String] the profile key
  # @return [Class] the normalizer class
  def self.normalizer_class_for(key)
    class_for(key, :normalizer)
  end

  # Resolves and returns the title extractor class for a given profile key
  # @param key [String] the profile key
  # @return [Class] the title extractor class
  def self.title_extractor_class_for(key)
    class_for(key, :title_extractor)
  end
end
