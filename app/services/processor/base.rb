module Processor
  # Base class for feed processors
  class Base
    # @param feed [Feed] the feed being processed
    # @param raw_data [String] raw feed data from loader
    def initialize(feed, raw_data)
      @feed = feed
      @raw_data = raw_data
    end

    # Processes raw feed data into structured entries
    # @return [Array<Hash>] processed feed entries
    # @abstract Subclasses must implement this method
    def process
      raise NotImplementedError, "Subclasses must implement #process method"
    end

    private

    attr_reader :feed, :raw_data
  end
end
