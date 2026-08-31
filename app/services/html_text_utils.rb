module HtmlTextUtils
  CONTENT_URL_SEPARATOR = " - "

  # WordPress replaces emoji characters with images in feed content
  # (wp_staticize_emoji), so they arrive as regular <img> tags.
  EMOJI_IMAGE_CLASSES = %w[wp-smiley emoji].freeze
  EMOJI_IMAGE_URL = %r{//s\.w\.org/images/core/emoji/}i

  def strip_html(text)
    return "" if text.blank?

    doc = Nokogiri::HTML::DocumentFragment.parse(text)
    doc.text.strip.gsub(/\s+/, " ")
  end

  def strip_html_preserving_paragraphs(text)
    return "" if text.blank?

    doc = Nokogiri::HTML::DocumentFragment.parse(text)
    doc.css("br").each { |node| node.after("\n") }
    doc.css("p").each { |node| node.after("\n\n") }

    doc.text.lines
      .map { |line| line.gsub(/[[:blank:]]+/, " ").strip }
      .join("\n")
      .strip
      .gsub(/\n{2,}/, "\n\n")
  end

  def extract_images(text)
    return [] if text.blank?

    doc = Nokogiri::HTML::DocumentFragment.parse(text)
    doc.css("img").filter_map { |image| image["src"] unless emoji_image?(image) }
  end

  def truncate_text(text, max_length: Post::MAX_CONTENT_LENGTH)
    return text if text.length <= max_length

    text.truncate(max_length, separator: " ", omission: "…")
  end

  # How much content survives once the URL is folded in. Callers that only
  # need to know whether the content fits ask here instead of re-deriving it.
  def content_fit_limit(url, max_content_length: Post::MAX_CONTENT_LENGTH, max_url_length: Post::MAX_URL_LENGTH)
    return max_content_length if url.blank? || url.length > max_url_length

    max_content_length - CONTENT_URL_SEPARATOR.length - url.length
  end

  def post_content_with_url(content, url, max_content_length: Post::MAX_CONTENT_LENGTH, max_url_length: Post::MAX_URL_LENGTH)
    # Do not include URL to the post content if the URL is too long
    url = nil if url.present? && url.length > max_url_length
    return url.to_s if content.blank?

    text = truncate_text(content, max_length: content_fit_limit(url, max_content_length:, max_url_length:))
    url.blank? ? text : "#{text}#{CONTENT_URL_SEPARATOR}#{url}"
  end

  private

  def emoji_image?(image)
    return true if image["class"].to_s.split.intersect?(EMOJI_IMAGE_CLASSES)

    image["src"].to_s.match?(EMOJI_IMAGE_URL)
  end
end
