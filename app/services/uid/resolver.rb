require "addressable/uri"

module Uid
  # Derives a stable post uid from an AI-extracted item, anchored to source
  # identity rather than generated content: summaries change every run, so a
  # content hash would break dedup. A usable deep-link permalink becomes a
  # normalized-URL uid that matches across runs; an item without one returns
  # nil and is dropped upstream.
  class Resolver
    TRACKING_PARAM = /\A(utm_|fbclid\z|gclid\z|mc_)/

    def self.call(item, clock:)
      new(item, clock).call
    end

    # The system-owned period for a digest run: the UTC date of the run. Shared
    # with the cadence guard so both agree on "this period" (spec §3).
    def self.digest_period(clock)
      clock.utc.to_date
    end

    # Period-keyed uid for a digest/standing-query item. Non-URL by construction,
    # so it never collides with a normalized permalink.
    def self.digest_period_uid(clock)
      "digest:#{digest_period(clock).iso8601}"
    end

    def initialize(item, clock)
      @item = item.is_a?(Hash) ? item : {}
      @clock = clock
    end

    def call
      return self.class.digest_period_uid(@clock) if digest?

      uri = deep_link
      uri && normalize(uri)
    end

    private

    attr_reader :item

    # The digest regime is signalled only by an explicit null source_url. A
    # missing key is malformed and an empty/unusable string is dropped — neither
    # is reinterpreted as a digest (spec §3's "unusable ≠ null").
    def digest?
      return false unless item.key?("source_url") || item.key?(:source_url)

      source_url_value.nil?
    end

    def source_url_value
      item.key?("source_url") ? item["source_url"] : item[:source_url]
    end

    def deep_link
      raw = (item["source_url"] || item[:source_url]).to_s.strip
      return if raw.empty?

      uri = parse_http(raw)
      return unless uri.is_a?(URI::HTTP) && uri.host.present?
      return if uri.path.delete_suffix("/").empty? && uri.query.nil? # bare homepage

      uri
    end

    # Non-ASCII/IDN permalinks make URI.parse raise, which used to silently drop
    # the item. Percent-encode the path and punycode the host via Addressable,
    # then retry — a Cyrillic URL should yield a stable uid, not vanish (spec §3).
    def parse_http(raw)
      URI.parse(raw)
    rescue URI::InvalidURIError
      parse_encoded(raw)
    end

    def parse_encoded(raw)
      URI.parse(Addressable::URI.parse(raw).normalize.to_s)
    rescue Addressable::URI::InvalidURIError, URI::InvalidURIError
      nil
    end

    def normalize(uri)
      # The uid is an identity key, not a fetch URL. Coerce the scheme to https
      # and drop a leading www. and default ports, so a model flipping
      # http/https/www between runs doesn't mint a duplicate repost (spec §3).
      uri.scheme = "https"
      uri.host = uri.host.downcase.sub(/\Awww\./, "")
      uri.port = nil if [80, 443].include?(uri.port)
      uri.fragment = nil
      uri.query = clean_query(uri.query)
      uri.path = uri.path.delete_suffix("/") unless uri.path == "/"
      uri.to_s
    end

    def clean_query(query)
      return if query.nil?

      kept = URI.decode_www_form(query).reject { |key, _| key.match?(TRACKING_PARAM) }
      kept.empty? ? nil : URI.encode_www_form(kept)
    end
  end
end
