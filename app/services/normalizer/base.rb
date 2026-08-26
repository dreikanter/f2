# Normalizers shape feed entry content for publication on FreeFeed, or
# reject the post with validation errors. The Post record persists either
# way.
module Normalizer
  class Base
    include HtmlTextUtils

    def initialize(feed_entry)
      @feed_entry = feed_entry
    end

    # Raises if the subclass produced a Post missing dedup or ordering
    # invariants; those are programming errors.
    def normalize
      post = build_post
      raise MissingUidError, "#{self.class.name} produced a Post with no uid" if post.uid.blank?
      raise MissingPublishedAtError, "#{self.class.name} produced a Post with no published_at" if post.published_at.blank?

      # TBD: Consider renaming this field
      post.validation_errors = validate_content
      post.status = post.validation_errors.empty? ? :enqueued : :rejected
      post
    end

    private

    attr_reader :feed_entry
    delegate :raw_data, to: :feed_entry

    def build_post
      Post.new(**extract_post_attributes.merge(default_post_attributes))
    end

    def default_post_attributes
      {
        feed: feed_entry.feed,
        feed_entry: feed_entry,
        uid: feed_entry.uid,
        published_at: normalize_published_at(feed_entry.published_at),
        status: :draft
      }
    end

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

    # Every attachment URL must be an absolute public http(s) URL or be
    # dropped (the attachment, not the post). Filtering here — the choke point
    # every normalizer flows through — keeps a relative or local-path value (e.g.
    # a feed's `<img src="/etc/passwd">`) from reaching FileBuffer at publish,
    # where File.exist? would read it off the server (LFI).
    def attachment_urls
      @attachment_urls ||= normalize_attachment_urls.select { |url| PublicUrl.safe?(url) }
    end

    def comments
      @comments ||= normalize_comments.map { |comment| Post.clamp_comment(comment) }
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
      errors.concat(images_only_errors)
      errors
    end

    # Feeds can opt into importing only posts that carry images. Image-less
    # entries are still saved as rejected posts (rather than dropped) so their
    # uids stay recorded and they're skipped normally on later refreshes.
    # Returned as a list so subclasses that build their own error set can
    # concat it without duplicating the rule (e.g. LlmNormalizer).
    def images_only_errors
      return [] unless feed_entry.feed.images_only?
      return [] unless attachment_urls.empty? && content.present?

      ["no_images"]
    end

    def normalize_published_at(published_at)
      return Time.current if published_at.nil? || published_at > Time.current
      published_at
    end

    def missing_content_and_images?
      content.blank? && attachment_urls.empty?
    end
  end
end
