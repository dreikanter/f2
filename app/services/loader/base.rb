module Loader
  class Base
    def initialize(feed, options = {})
      @feed = feed
      @options = options
    end

    def load
      raise NotImplementedError, "Subclasses must implement #load method"
    end

    private

    attr_reader :feed, :options
  end
end
