module HtmlTextUtils
  CONTENT_URL_SEPARATOR = " - "

  def strip_html(text)
    return "" if text.blank?

    doc = Nokogiri::HTML::DocumentFragment.parse(text)
    doc.text.strip.gsub(/\s+/, " ")
  end

  def extract_images(text)
    return [] if text.blank?

    doc = Nokogiri::HTML::DocumentFragment.parse(text)
    doc.css("img").map { |image| image["src"] }.compact
  end

  def truncate_text(text, max_length: Post::MAX_CONTENT_LENGTH)
    return text if text.length <= max_length

    text.truncate(max_length, separator: " ")
  end

  def post_content_with_url(text, url, max_length: Post::MAX_CONTENT_LENGTH)
    return text if url.blank?

    separator_length = CONTENT_URL_SEPARATOR.length
    url_length = url.length
    min_required_length = separator_length + url_length

    return nil if min_required_length > max_length

    max_text_length = max_length - min_required_length
    truncated_text = truncate_text(text, max_length: max_text_length)
    "#{truncated_text}#{CONTENT_URL_SEPARATOR}#{url}"
  end
end
