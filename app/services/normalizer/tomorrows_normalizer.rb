module Normalizer
  class TomorrowsNormalizer < RssNormalizer
    PROFILE_KEY = "tomorrows"
    MAX_COMMENTS = 4

    private

    def normalize_content
      title = raw_data["title"] || ""
      title.strip
    end

    def normalize_comments
      text = story_text
      return [] if text.blank?

      comments = []
      while text.present? && comments.size < MAX_COMMENTS
        if comments.size == MAX_COMMENTS - 1
          comments << truncate_text(text, max_length: Post::MAX_COMMENT_LENGTH)
          break
        end

        boundary = comment_boundary(text)
        comments << text.slice!(0, boundary).rstrip
        text = text.lstrip
      end
      comments
    end

    def comment_boundary(text)
      limit = Post::MAX_COMMENT_LENGTH
      return text.length if text.length <= limit

      excerpt = text[0, limit + 1]
      excerpt.rindex(/\n\n/) || excerpt.rindex(/\n/) ||
        excerpt.rindex(/[.!?]["”’']?\K\s+/) || excerpt.rindex(/\s+/) || limit
    end

    def story_text
      url = raw_data["link"] || ""
      page = page_fetcher.fetch(url)
      if page
        extract_story_from_page(page, url)
      else
        fallback_story_text
      end
    end

    def extract_story_from_page(html, url)
      doc = Nokogiri::HTML(html)
      node = doc.css(".entry-content").first

      unless node
        Rails.error.report(
          StandardError.new("tomorrows: page #{url} fetched but .entry-content missing — markup changed?"),
          context: { profile: PROFILE_KEY, feed_id: feed_entry.feed&.id, uid: feed_entry.uid, url: url }
        )
        return nil
      end

      paragraphs = node.css("p").map { |p| strip_html_preserving_paragraphs(p.to_html) }
      paragraphs.reject(&:blank?).join("\n\n")
    end

    def fallback_story_text
      raw = raw_data["content"] || raw_data["summary"] || ""
      text = strip_html_preserving_paragraphs(raw)
      text.presence
    end
  end
end
