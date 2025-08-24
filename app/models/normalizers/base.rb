module Normalizers
  class Base
    include Discoverable

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
