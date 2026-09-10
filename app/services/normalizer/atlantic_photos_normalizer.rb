module Normalizer
  class AtlanticPhotosNormalizer < RssNormalizer
    private

    def normalize_content
      title = strip_html(raw_data["title"])
      author = strip_html(raw_data["author"])
      author.present? ? "#{title} (#{author})" : title
    end

    def normalize_comments
      captions = Nokogiri::HTML(raw_data["content"].to_s).css("figure").filter_map do |figure|
        image = figure.at_css("img")
        next unless image && PublicUrl.safe?(image["src"])

        [image["src"], image["alt"], feed_text(figure.at_css("figcaption")&.to_html)].compact_blank.uniq.join("\n\n")
      end
      [feed_text(raw_data["summary"]), *captions].compact_blank
    end

    def normalize_attachment_urls
      inline_images.presence || image_urls
    end
  end
end
