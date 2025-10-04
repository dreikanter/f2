# Base class for feed entry normalizers
#
# Normalizer should normalize the feed entry content to make it compatible with
# publication on Freefeed. If normalization is not possible, normalizer should
# reject the post with a list of validation errors. The Post record can always
# be persisted regardless of whether normalization is performed.
#
module Normalizer
  class Base
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
        published_at: normalize_published_at(feed_entry.published_at),
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

    def normalize_published_at(published_at)
      return Time.current if published_at > Time.current
      published_at
    end

    def missing_content_and_images?(post)
      post.content.blank? && post.attachment_urls.empty?
    end

    def raw_data
      feed_entry.raw_data
    end

    def strip_html(text)
      return "" if text.blank?

      doc = Nokogiri::HTML::DocumentFragment.parse(text)
      doc.text.strip.gsub(/\s+/, " ")
    end

    def extract_images_from_content(content)
      return [] if content.blank?

      doc = Nokogiri::HTML::DocumentFragment.parse(content)
      doc.css("img").map { |img| img["src"] }.compact
    end

    def truncate_content(content)
      return content if content.length <= Post::MAX_CONTENT_LENGTH

      content.truncate(Post::MAX_CONTENT_LENGTH, separator: " ")
    end

    def normalize_source_url(url)
      return "" if url.blank?

      URI.parse(url)
      url
    rescue URI::InvalidURIError
      ""
    end
  end
end
