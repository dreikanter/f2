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

    CONTENT_URL_SEPARATOR = " - "

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
      post_attributes = extract_post_attributes(feed_entry.raw_data)

      Post.new(
        feed: feed_entry.feed,
        feed_entry: feed_entry,
        uid: feed_entry.uid,
        published_at: normalize_published_at(feed_entry.published_at),
        status: :draft,
        validation_errors: [],
        **post_attributes
      )
    end

    # Extracts post attributes from raw data
    # @param raw_data [Hash] the raw feed entry data
    # @return [Hash] post attributes (source_url, content, attachment_urls, comments)
    def extract_post_attributes(raw_data)
      {
        source_url: extract_source_url(raw_data),
        content: extract_content(raw_data),
        attachment_urls: extract_attachment_urls(raw_data),
        comments: extract_comments(raw_data)
      }
    end

    def extract_source_url(raw_data)
      raise NotImplementedError, "Subclasses must implement #extract_source_url"
    end

    def extract_content(raw_data)
      raise NotImplementedError, "Subclasses must implement #extract_content"
    end

    def extract_attachment_urls(raw_data)
      []
    end

    def extract_comments(raw_data)
      []
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

    def join_content_with_url(text, url)
      return { content: text, error: nil } if url.blank?

      separator_length = CONTENT_URL_SEPARATOR.length
      url_length = url.length
      min_required_length = separator_length + url_length

      if min_required_length > Post::MAX_CONTENT_LENGTH
        return { content: nil, error: "url_too_long" }
      end

      max_text_length = Post::MAX_CONTENT_LENGTH - min_required_length
      truncated_text = truncate_text(text, max_length: max_text_length)
      content = "#{truncated_text}#{CONTENT_URL_SEPARATOR}#{url}"

      { content: content, error: nil }
    end
  end
end
