module Loaders
  class Base
    def self.descendants
      ObjectSpace.each_object(Class).select { |klass| klass < self }
    end

    def self.available_loaders
      descendants.map { |klass| klass.name.demodulize.gsub(/Loader$/, "") }.sort
    end

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
