module Normalizer
  class Base
    def initialize(feed_entry)
      @feed_entry = feed_entry
    end

    def normalize
      post = build_post
      post.validation_errors = validate_post(post)
      post.status = post.validation_errors.empty? ? :enqueued : :rejected
      post
    end

    private

    attr_reader :feed_entry

    def build_post
      raise NotImplementedError, "Subclasses must implement #build_post method"
    end

    def validate_post(post)
      raise NotImplementedError, "Subclasses must implement #validate_post method"
    end
  end
end
