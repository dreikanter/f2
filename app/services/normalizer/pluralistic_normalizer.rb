module Normalizer
  class PluralisticNormalizer < RssNormalizer
    # WordPress Photon CDN host pattern. A full regex anchor is used here
    # (^...$), so this cannot be bypassed by a hostname like
    # "evil-i0.wp.com" or "i0.wp.com.evil.com" — the anchor ensures an
    # exact match against the host segment, which is why plain end_with?
    # is not used for the CodeQL-flagged domain-equality checks elsewhere.
    PHOTON_HOST_PATTERN = /\Ai\d+\.wp\.com\z/

    private

    def normalize_content
      title = raw_data.dig("title") || ""
      title.strip
    end

    def normalize_attachment_urls
      [cover_image_url].compact
    rescue StandardError
      super
    end

    def cover_image_url
      url = raw_data.dig("link") || ""
      page = fetch_page(url)
      return nil if page.nil?

      doc = Nokogiri::HTML(page)
      img = doc.css("img").first

      if img.nil?
        Rails.error.report(
          StandardError.new("pluralistic: page #{url} fetched but no <img> found — markup changed?"),
          context: { profile: "pluralistic", feed_id: feed_entry.feed&.id, entry_uid: feed_entry.uid, entry_url: url }
        )
        return nil
      end

      src = img["src"]
      return nil if src.blank?

      rewrite_photon_url(src)
    end

    def rewrite_photon_url(url)
      uri = URI.parse(url)
      return url unless PHOTON_HOST_PATTERN.match?(uri.host.to_s)

      # Photon CDN URL format: https://i0.wp.com/<real-host>/<path>?query
      # First path segment after leading slash is the real hostname.
      segments = uri.path.split("/", 3)
      real_host = segments[1]
      remaining_path = segments[2].present? ? "/#{segments[2]}" : "/"

      direct = "https://#{real_host}#{remaining_path}"
      uri.query.present? ? "#{direct}?#{uri.query}" : direct
    end

    def fetch_page(url)
      return nil if url.blank?

      response = HttpClient.build.get(url)

      unless response.success?
        Rails.logger.warn(
          "pluralistic: page fetch failed (HTTP #{response.status}), skipping images " \
          "[feed_id=#{feed_entry.feed&.id} uid=#{feed_entry.uid} url=#{url}]"
        )
        return nil
      end

      response.body
    rescue HttpClient::Error => e
      Rails.logger.warn(
        "pluralistic: page fetch error (#{e.class}: #{e.message}), skipping images " \
        "[feed_id=#{feed_entry.feed&.id} uid=#{feed_entry.uid} url=#{url}]"
      )
      nil
    end
  end
end
