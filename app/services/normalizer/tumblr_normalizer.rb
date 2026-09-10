module Normalizer
  class TumblrNormalizer < RssNormalizer
    private

    def normalize_content
      strip_html(raw_data["title"]).presence || paragraphs.first || ""
    end

    def normalize_comments
      (paragraphs.reject { |paragraph| paragraph == normalize_content } + image_descriptions).uniq
    end

    def normalize_attachment_urls
      document.css("img").filter_map do |image|
        candidates = image["srcset"].to_s.split(",").filter_map do |candidate|
          url, width = candidate.strip.split
          [url, width.to_i] if width&.match?(/\A\d+w\z/) && PublicUrl.safe?(url)
        end
        candidates.max_by(&:last)&.first || image["src"]
      end.uniq
    end

    def paragraphs
      @paragraphs ||= feed_text(document.to_html).split("\n\n").compact_blank
    end

    def image_descriptions
      document.css("img[alt]").filter_map { |image| image["alt"].presence }
    end

    def document
      @document ||= Nokogiri::HTML::DocumentFragment.parse(raw_data["summary"].to_s).tap do |doc|
        doc.css(".tmblr-alt-text-helper").remove
      end
    end
  end
end
