module Uid
  # Derives a stable post uid from an AI-extracted item, anchored to source
  # identity rather than generated content: summaries change every run, so a
  # content hash would break dedup. A usable deep-link permalink becomes a
  # normalized-URL uid that matches across runs; an item without one returns
  # nil and is dropped upstream.
  class Resolver
    TRACKING_PARAM = /\A(utm_|fbclid\z|gclid\z|mc_)/

    def self.call(item)
      new(item).call
    end

    def initialize(item)
      @item = item.is_a?(Hash) ? item : {}
    end

    def call
      uri = deep_link
      uri && normalize(uri)
    end

    private

    attr_reader :item

    def deep_link
      raw = (item["source_url"] || item[:source_url]).to_s.strip
      return if raw.empty?

      uri = URI.parse(raw)
      return unless uri.is_a?(URI::HTTP) && uri.host.present?
      return if uri.path.delete_suffix("/").empty? && uri.query.nil? # bare homepage

      uri
    rescue URI::InvalidURIError
      nil
    end

    def normalize(uri)
      uri.scheme = uri.scheme.downcase
      uri.host = uri.host.downcase
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
