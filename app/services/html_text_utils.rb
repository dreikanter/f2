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

  def post_content_with_url(content, url, max_content_length: Post::MAX_CONTENT_LENGTH, max_url_length: Post::MAX_URL_LENGTH)
    return content if url.blank?

    # Do not include URL to the post content if the URL is too long
    if url.length > max_url_length
      return truncate_text(content, max_length: max_content_length)
    end

    # If content is blank, just return the URL
    return url if content.blank?

    # Both content and URL are present, join with separator
    max_text_length = max_content_length - CONTENT_URL_SEPARATOR.length - url.length
    truncated_text = truncate_text(content, max_length: max_text_length)
    "#{truncated_text}#{CONTENT_URL_SEPARATOR}#{url}"
  end
end
