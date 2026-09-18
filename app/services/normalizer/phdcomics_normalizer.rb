module Normalizer
  class PhdcomicsNormalizer < RssNormalizer
    private

    def normalize_content
      strip_html(raw_data["title"])
    end
  end
end
