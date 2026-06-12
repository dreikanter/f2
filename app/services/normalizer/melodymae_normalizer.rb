module Normalizer
  class MelodymaeNormalizer < RssNormalizer
    private

    PHOTON_CDN_PATTERN = %r{https://i\d+\.wp\.com/}

    def normalize_content
      (raw_data.dig("title") || "").strip
    end

    def normalize_comments
      text = strip_html(raw_data.dig("content") || "")
      return [] if text.blank?

      [truncate_text(text, max_length: 1500)]
    end

    def normalize_attachment_urls
      image_url = extract_images(raw_data.dig("content") || "").first
      return [] if image_url.blank?

      image_url = rewrite_photon_url(image_url)

      unless image_reachable?(image_url)
        Rails.logger.warn(
          "[melodymae] Skipping unreachable image: #{image_url.inspect} " \
          "(feed_id=#{feed_entry.feed&.id}, uid=#{feed_entry.uid.inspect})"
        )
        return []
      end

      [image_url]
    end

    def rewrite_photon_url(url)
      url.sub(PHOTON_CDN_PATTERN, "https://")
    end

    def image_reachable?(url)
      response = HttpClient.build.get(url)
      response.success?
    rescue HttpClient::Error => e
      Rails.logger.warn(
        "[melodymae] Image fetch error: #{e.message} for #{url.inspect} " \
        "(feed_id=#{feed_entry.feed&.id}, uid=#{feed_entry.uid.inspect})"
      )
      false
    end
  end
end
