module Normalizer
  # Base class for feed entry normalizers
  class Base
    # @param feed_entry [FeedEntry] the feed entry to normalize
    def initialize(feed_entry)
      @feed_entry = feed_entry
    end

    # Normalizes feed entry into a Post with validation
    # @return [Post] post with status set based on validation
    def normalize
      post = build_post
      post.validation_errors = validate_post(post)
      post.status = post.validation_errors.empty? ? :enqueued : :rejected
      post
    end

    private

    attr_reader :feed_entry

    # Builds Post from feed entry data
    # @return [Post] new post instance
    # @abstract Subclasses must implement this method
    def build_post
      raise NotImplementedError, "Subclasses must implement #build_post method"
    end

    # Validates post data
    # @param post [Post] the post to validate
    # @return [Array<String>] validation error codes
    # @abstract Subclasses must implement this method
    def validate_post(post)
      raise NotImplementedError, "Subclasses must implement #validate_post method"
    end
  end
end
