module Normalizers
  class Base
    def self.descendants
      ObjectSpace.each_object(Class).select { |klass| klass < self }
    end

    def self.available_normalizers
      descendants.map { |klass| klass.name.demodulize.gsub(/Normalizer$/, "") }.sort
    end

    def initialize(feed, processed_items)
      @feed = feed
      @processed_items = processed_items
    end

    def normalize
      raise NotImplementedError, "Subclasses must implement #normalize method"
    end

    private

    attr_reader :feed, :processed_items
  end
end
