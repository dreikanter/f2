module Loader
  # Base class for feed loaders
  class Base
    # @param feed [Feed] the feed to load from
    # @param options [Hash] optional configuration
    def initialize(feed, options = {})
      @feed = feed
      @options = options
    end

    # Loads raw data from feed source
    # @return [Object] payload for the profile's processor
    # @abstract Subclasses must implement this method
    def load
      raise NotImplementedError, "Subclasses must implement #load method"
    end

    private

    attr_reader :feed, :options
  end
end
