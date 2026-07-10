module TitleExtractor
  # Suggests a feed title for a Bluesky account. Prefers the account's
  # display name from the fetched page's og:title, falling back to the
  # @handle from the input.
  class BlueskyTitleExtractor < Base
    def title
      og_title.presence || handle.presence
    end

    private

    def og_title
      return nil if fetched_body.blank?

      doc = Nokogiri::HTML.parse(fetched_body, nil, "UTF-8")
      doc.at_css('meta[property="og:title"]')&.[]("content")&.strip
    rescue StandardError
      nil
    end

    def handle
      name = input.to_s.strip.sub(/\A@/, "").sub(%r{\Ahttps?://}i, "")
                  .sub(%r{\A(?:www\.)?bsky\.app/profile/}i, "")
                  .split("/").first.to_s
      name.empty? ? "" : "@#{name}"
    end
  end
end
