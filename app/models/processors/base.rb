module Processors
  class Base
    def self.descendants
      ObjectSpace.each_object(Class).select { |klass| klass < self }
    end

    def self.available_processors
      descendants.map { |klass| klass.name.demodulize.gsub(/Processor$/, "") }.sort
    end

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
