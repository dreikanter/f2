# Base class for feed entry normalizers
#
# Normalizer should normalize the feed entry content to make it compatible with
# publication on Freefeed. If normalization is not possible, normalizer should
# reject the post with a list of validation errors. The Post record can always
# be persisted regardless of whether normalization is performed.
#
module Normalizer
  class Base
    include HtmlTextUtils

    # @param feed_entry [FeedEntry] the feed entry to normalize
    def initialize(feed_entry)
      @feed_entry = feed_entry
    end

    # Normalizes feed entry into a Post with validation
    #
    # @return [Post] post with status set based on validation
    def normalize
      post = build_post
      # TBD: Consider renaming this field
      post.validation_errors = validate_content
      post.status = post.validation_errors.empty? ? :enqueued : :rejected
      post
    end

    private

    attr_reader :feed_entry
    delegate :raw_data, to: :feed_entry

    # Builds Post from feed entry data
    # @return [Post] new post instance
    def build_post
      post_attributes = extract_post_attributes.merge(
        feed: feed_entry.feed,
        feed_entry: feed_entry,
        uid: feed_entry.uid,
        published_at: normalize_published_at(feed_entry.published_at),
        status: :draft
      )

      Post.new(**post_attributes)
    end

    # Extracts post attributes from raw data
    # @return [Hash] post attributes (source_url, content, attachment_urls, comments)
    def extract_post_attributes
      {
        source_url: source_url,
        content: content,
        attachment_urls: attachment_urls,
        comments: comments
      }
    end

    def source_url
      @source_url ||= normalize_source_url
    end

    def content
      @content ||= normalize_content
    end

    def attachment_urls
      @attachment_urls ||= normalize_attachment_urls
    end

    def comments
      @comments ||= normalize_comments
    end

    def normalize_source_url
      raise NotImplementedError, "Subclasses must implement #normalize_source_url"
    end

    def normalize_content
      raise NotImplementedError, "Subclasses must implement #normalize_content"
    end

    def normalize_attachment_urls
      []
    end

    def normalize_comments
      []
    end

    def validate_content
      errors = []
      errors << "no_content_or_images" if missing_content_and_images?
      errors
    end

    def normalize_published_at(published_at)
      return Time.current if published_at > Time.current
      published_at
    end

    def missing_content_and_images?
      content.blank? && attachment_urls.empty?
    end
  end
end
