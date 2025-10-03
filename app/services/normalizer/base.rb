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
      # TBD: Consider renamint this field
      post.validation_errors = validate_post(post)
      post.status = post.validation_errors.empty? ? :enqueued : :rejected
      post
    end

    private

    attr_reader :feed_entry

    # Builds Post from feed entry data
    # @return [Post] new post instance
    def build_post
      content_attributes = extract_content_attributes(feed_entry.raw_data)

      Post.new(
        feed: feed_entry.feed,
        feed_entry: feed_entry,
        uid: feed_entry.uid,
        published_at: feed_entry.published_at,
        status: :draft,
        validation_errors: [],
        **content_attributes
      )
    end

    # Extracts content-specific attributes from raw data
    # @param raw_data [Hash] the raw feed entry data
    # @return [Hash] content attributes (link, text, attachment_urls, comments)
    # @abstract Subclasses must implement this method
    def extract_content_attributes(raw_data)
      raise NotImplementedError, "Subclasses must implement #extract_content_attributes method"
    end

    def validate_post(post)
      errors = []
      errors << "no_content_or_images" if missing_content_and_images?(post)
      errors
    end

    def missing_content_and_images?(post)
      post.content.blank? && post.attachment_urls.empty?
    end
  end
end
