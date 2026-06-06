module PostHelper
  def format_post_content(content)
    return "" if content.blank?

    # Trim leading and trailing whitespace
    trimmed = content.strip

    # Normalize CRLF to LF (browsers submit \r\n, but we split on \n)
    normalized = trimmed.gsub(/\r\n/, "\n")

    # Split by 2+ line breaks to create paragraphs
    paragraphs = normalized.split(/\n{2,}/)

    # Process each paragraph
    formatted_paragraphs = paragraphs.map do |para|
      # Convert URLs to links and escape all text
      linked = auto_link_urls(para)

      # Convert single line breaks to <br> tags
      with_breaks = linked.gsub(/\n/, "<br>")

      # Wrap in paragraph tag
      tag.p(with_breaks.html_safe, class: "mb-4 last:mb-0")
    end

    safe_join(formatted_paragraphs)
  end

  def post_status_badge_color(status)
    case status.to_s
    when "enqueued"
      :blue
    when "published"
      :green
    when "failed"
      :red
    when "rejected"
      :orange
    else
      :gray
    end
  end

  private

  # Convert URLs in text to clickable links and escape all content
  def auto_link_urls(text)
    # Regex to match URLs (http, https, ftp)
    url_regex = %r{
      \b
      (https?://|ftp://)
      [^\s<>]+
    }x

    last_end = 0
    result = []

    text.scan(url_regex) do
      match_start = Regexp.last_match.begin(0)
      match_end = Regexp.last_match.end(0)
      url = Regexp.last_match[0]

      # Escape text before this URL
      result << ERB::Util.html_escape(text[last_end...match_start])

      # Escape URL for safe embedding in href attribute and link text
      escaped_url = ERB::Util.html_escape(url)
      result << %(<a href="#{escaped_url}" target="_blank" rel="noopener" class="font-medium text-sky-600 underline underline-offset-4 transition hover:text-sky-500">#{escaped_url}</a>)

      last_end = match_end
    end

    # Escape remaining text after last URL
    result << ERB::Util.html_escape(text[last_end..])

    result.join
  end
end
