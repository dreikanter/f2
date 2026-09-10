module Normalizer
  class LunarbaboonNormalizer < RssNormalizer
    private

    def attachable_images(html)
      extract_images(html).map { |url| url.gsub(" ", "%20") }.select { |url| PublicUrl.safe?(url) }
    end
  end
end
