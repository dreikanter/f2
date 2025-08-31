module Loaders
  class Base
    def initialize(feed)
      @feed = feed
    end

    def load
      raise NotImplementedError, "Subclasses must implement #load method"
    end

    private

    attr_reader :feed
  end
end
