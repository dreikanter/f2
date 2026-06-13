module TitleExtractor
  # Suggests a feed title for a YouTube channel.
  #
  # A channel URL resolves to an HTML page, so the fetched body carries the
  # channel name in its og:title meta tag rather than an RSS/Atom feed. When
  # the input is the Atom feed URL directly, the body is the feed XML, so we
  # fall back to its <title>. As a last resort we derive a handle from the URL.
  class YoutubeTitleExtractor < Base
    def title
      og_title.presence || atom_title.presence || handle.presence
    end

    private

    def og_title
      return nil if fetched_body.blank?

      doc = Nokogiri::HTML.parse(fetched_body, nil, "UTF-8")
      doc.at_css('meta[property="og:title"]')&.[]("content")&.strip
    rescue StandardError
      nil
    end

    def atom_title
      RssTitleExtractor.new(input, fetched_body).title
    end

    def handle
      segment = URI.parse(input.to_s).path.to_s.split("/").find(&:present?)
      segment if segment&.start_with?("@")
    rescue URI::InvalidURIError
      nil
    end
  end
end
