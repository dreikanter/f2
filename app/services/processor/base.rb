module Processor
  # The outcome of parsing a payload: the entries it yielded, plus whether the
  # payload was recognizable as this processor's format. The flag lets callers
  # tell an empty-but-valid source (a real feed with no posts) from one whose
  # entries are empty only because the payload was unreadable.
  Result = Data.define(:entries, :recognized) do
    def recognized? = recognized
  end

  # Base class for feed processors
  class Base
    # @param feed [Feed] the feed being processed
    # @param raw_data [String] raw feed data from loader
    def initialize(feed, raw_data)
      @feed = feed
      @raw_data = raw_data
    end

    # Parses raw feed data into a Result (entries plus recognition).
    # @return [Processor::Result]
    # @abstract Subclasses must implement this method
    def process
      raise NotImplementedError, "Subclasses must implement #process method"
    end

    private

    attr_reader :feed, :raw_data
  end
end
