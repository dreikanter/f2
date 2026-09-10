module Normalizer
  class HackernewsNormalizer < Base
    private

    def normalize_source_url
      "https://news.ycombinator.com/item?id=#{raw_data.fetch('id')}"
    end

    def normalize_content
      url = raw_data["url"].presence || source_url
      post_content_with_url(strip_html(raw_data["title"]), url)
    end

    def normalize_comments
      ["#{raw_data.fetch('score')} points / #{source_url}"]
    end
  end
end
