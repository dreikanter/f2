module Normalizer
  # Savage Chickens names each strip in the title and keeps the caption in the
  # entry body. Generic RSS handling prefers the body, which buries the strip's
  # name and drops the caption. Lead with the title instead and move the
  # caption into comments.
  class SavagechickensNormalizer < RssNormalizer
    private

    def normalize_content
      strip_html(raw_data["title"])
    end

    # WordPress truncates the description into an excerpt once a post runs
    # long, so read the caption from content:encoded and keep the description
    # only as a fallback. The cartoon itself sits in a paragraph of its own and
    # strips down to nothing, so it drops out with the other blanks.
    def normalize_comments
      caption_html = raw_data["content"].presence || raw_data["summary"]
      strip_html_preserving_paragraphs(caption_html).split("\n\n").compact_blank
    end
  end
end
