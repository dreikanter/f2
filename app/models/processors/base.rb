module Processors
  class Base
    include Discoverable

    def initialize(feed, raw_data)
      @feed = feed
      @raw_data = raw_data
    end

    def process
      raise NotImplementedError, "Subclasses must implement #process method"
    end

    private

    attr_reader :feed, :raw_data
  end
end
