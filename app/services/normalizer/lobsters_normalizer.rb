module Normalizer
  class LobstersNormalizer < RssNormalizer
    private

    def normalize_content
      title = raw_data["title"] || ""
      title.strip
    end

    def normalize_comments
      return [] if discussion_url.blank?

      [["Comments: #{discussion_url}", tags].compact_blank.join(" ")]
    end

    # The entry guid points at the lobste.rs discussion page, while the
    # entry link points at the external story.
    def discussion_url
      raw_data["id"]
    end

    def tags
      categories = raw_data["categories"] || []
      categories.map { |category| "##{category}" }.join(" ")
    end
  end
end
