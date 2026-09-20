module Uid
  # Normalizes permalink identity across AI extraction and webhook deliveries.
  class Resolver
    TRACKING_PARAM = /\A(utm_|fbclid\z|gclid\z|mc_)/

    def self.from_url(url)
      uri = deep_link(url)
      uri && normalize(uri)
    end

    class << self
      private

      def deep_link(url)
        raw = url.to_s.strip
        return if raw.empty?

        uri = parse_http(raw)
        return unless uri.is_a?(URI::HTTP) && uri.host.present?
        return if uri.path.delete_suffix("/").empty? && uri.query.nil? # bare homepage

        uri
      end

      # URI.parse rejects non-ASCII/IDN permalinks. Percent-encode the path and
      # punycode the host via Addressable, then retry, so a Cyrillic URL yields
      # a stable uid instead of losing the item.
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
        # The uid is an identity key, not a fetch URL. Coerce the scheme to
        # https and drop a leading www. and default ports, so a model flipping
        # http/https/www between runs doesn't mint a duplicate repost.
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
end
