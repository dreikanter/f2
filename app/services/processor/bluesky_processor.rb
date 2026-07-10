module Processor
  # Parses a Bluesky getAuthorFeed JSON payload into FeedEntry objects. Only
  # the author's own top-level posts survive: reposts (items carrying a
  # `reason`) and replies are skipped. Truncated link text is expanded to the
  # full target URL from the post's facets, and embedded images, gallery
  # items, and video thumbnails are collected as attachment candidates.
  class BlueskyProcessor < Base
    LINK_FACET = "app.bsky.richtext.facet#link".freeze
    # Placeholder the AppView serves when an account's handle no longer
    # resolves; permalinks built from it are dead, the DID form works.
    INVALID_HANDLE = "handle.invalid".freeze

    def process
      items = feed_items
      Result.new(
        entries: Array(items).filter_map { |item| build_entry(item) },
        recognized: !items.nil?
      )
    end

    private

    # The feed array, or nil when the payload isn't a getAuthorFeed response.
    def feed_items
      parsed = JSON.parse(raw_data.to_s)
      items = parsed.is_a?(Hash) ? parsed["feed"] : nil
      items.is_a?(Array) ? items : nil
    rescue JSON::ParserError
      nil
    end

    def build_entry(item)
      return nil if item["reason"].present? || item["reply"].present?

      post = item["post"]
      return nil unless post.is_a?(Hash)

      uid = post["uri"].presence
      return nil unless uid

      published_at = parse_time(post.dig("record", "createdAt"))
      return nil unless published_at

      FeedEntry.new(
        feed: feed,
        uid: uid,
        published_at: published_at,
        status: :pending,
        raw_data: {
          "uid" => uid,
          "url" => post_url(post),
          "text" => post_text(post["record"] || {}),
          "images" => embed_images(post["embed"] || {})
        }
      )
    end

    # The public permalink: bsky.app/profile/<actor>/post/<rkey>, where the
    # rkey is the last segment of the post's at:// URI.
    def post_url(post)
      rkey = post["uri"].to_s.split("/").last
      "https://bsky.app/profile/#{post_actor(post)}/post/#{rkey}"
    end

    def post_actor(post)
      handle = post.dig("author", "handle").presence
      handle = nil if handle == INVALID_HANDLE
      handle || post.dig("author", "did")
    end

    # Bluesky truncates long URLs in the display text ("example.com/long-pa...")
    # and carries the full target in a link facet addressed by byte range.
    # Splice the full URLs back in, working bytewise from the end so earlier
    # ranges stay valid.
    def post_text(record)
      text = record["text"].to_s
      facets = link_facets(record)
      return text if facets.empty?

      bytes = text.dup.force_encoding(Encoding::BINARY)
      facets.sort_by { |facet| -facet[:start] }.each do |facet|
        next if facet[:start].negative? || facet[:start] >= facet[:stop] || facet[:stop] > bytes.bytesize

        bytes[facet[:start]...facet[:stop]] = facet[:uri].dup.force_encoding(Encoding::BINARY)
      end

      expanded = bytes.force_encoding(Encoding::UTF_8)
      expanded.valid_encoding? ? expanded : text
    end

    def link_facets(record)
      Array(record["facets"]).filter_map do |facet|
        index = facet["index"]
        next unless index.is_a?(Hash)

        uri = Array(facet["features"]).filter_map { |feature| feature["uri"] if feature["$type"] == LINK_FACET }.first
        next if uri.blank?

        { start: index["byteStart"].to_i, stop: index["byteEnd"].to_i, uri: uri }
      end
    end

    def embed_images(embed)
      case embed["$type"]
      when "app.bsky.embed.images#view"
        Array(embed["images"]).filter_map { |image| image["fullsize"] }
      when "app.bsky.embed.gallery#view"
        Array(embed["items"]).filter_map { |item| item["fullsize"] }
      when "app.bsky.embed.video#view"
        [embed["thumbnail"]].compact
      when "app.bsky.embed.recordWithMedia#view"
        embed_images(embed["media"] || {})
      else
        []
      end.uniq
    end

    def parse_time(value)
      return nil if value.blank?

      Time.iso8601(value)
    rescue ArgumentError
      nil
    end
  end
end
