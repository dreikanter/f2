module HtmlTextUtils
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
end
