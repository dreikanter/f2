module Processor
  # Parses a JSON Feed (https://jsonfeed.org) into FeedEntry objects.
  #
  # The emitted raw_data mirrors the shape RssProcessor produces, so the
  # generic image/URL handling in RssNormalizer applies. JSON Feed's
  # `image`, `banner_image`, and image-typed `attachments` are folded into
  # the same `enclosures` array RSS uses.
  class JsonFeedProcessor < Base
    def process
      feed_data = JSON.parse(raw_data)
      feed_data = {} unless feed_data.is_a?(Hash)

      Result.new(
        entries: build_entries(feed_data),
        recognized: recognizable?(feed_data)
      )
    end

    private

    def build_entries(feed_data)
      feed_authors = feed_data["authors"]

      Array(feed_data["items"]).filter_map do |item|
        next unless item.is_a?(Hash)

        FeedEntry.new(
          feed: feed,
          uid: extract_uid(item),
          # date_published is optional in JSON Feed; fall back to now so
          # date-less items still import (see PassthroughProcessor).
          published_at: parse_time(item["date_published"]) || Time.current,
          status: :pending,
          raw_data: sanitize_item(item, feed_authors)
        )
      end
    end

    # A real JSON Feed always declares its version and a title; either an
    # items array or a title means the payload parsed as a genuine feed
    # rather than unrelated JSON that happened to mention the marker.
    def recognizable?(feed_data)
      return false unless feed_data["version"].to_s.include?("jsonfeed.org/version/")

      feed_data["items"].is_a?(Array) || feed_data["title"].present?
    end

    def extract_uid(item)
      id = item["id"]
      id = id.to_s if id.is_a?(Numeric)
      id.presence || item["url"]
    end

    def sanitize_item(item, feed_authors)
      {
        "id" => item["id"],
        "title" => item["title"],
        "url" => item["url"],
        "link" => item["url"],
        "external_url" => item["external_url"],
        "summary" => item["summary"],
        "content" => item["content_html"].presence || item["content_text"],
        "published" => parse_time(item["date_published"])&.rfc3339,
        "updated" => parse_time(item["date_modified"])&.rfc3339,
        "author" => author_name(item, feed_authors),
        "categories" => Array(item["tags"]),
        "enclosures" => extract_enclosures(item)
      }
    end

    # JSON Feed 1.1 carries a list of authors; 1.0 a single author object.
    # An item without its own author inherits the feed-level authors. Either
    # way each author is an object whose `name` is what we keep.
    def author_name(item, feed_authors)
      authors = item["authors"].presence || [item["author"]].compact.presence || feed_authors
      author = Array(authors).find { |entry| entry.is_a?(Hash) && entry["name"].present? }
      author&.dig("name")
    end

    def extract_enclosures(item)
      images = [item["image"], item["banner_image"]].compact_blank.map { |url| { "url" => url, "type" => nil } }
      attachments = Array(item["attachments"]).filter_map do |attachment|
        next unless attachment.is_a?(Hash) && attachment["url"].present?

        { "url" => attachment["url"], "type" => attachment["mime_type"] }
      end
      images + attachments
    end

    def parse_time(value)
      return nil if value.blank?

      Time.parse(value.to_s)
    rescue ArgumentError
      nil
    end
  end
end
