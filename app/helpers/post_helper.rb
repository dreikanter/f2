module PostHelper
  def format_post_content(content)
    return "" if content.blank?

    trimmed = content.strip
    normalized = trimmed.gsub(/\r\n/, "\n")
    paragraphs = normalized.split(/\n{2,}/)

    formatted_paragraphs = paragraphs.map do |para|
      linked = auto_link_urls(para)
      with_breaks = linked.gsub(/\n/, "<br>")
      tag.p(with_breaks.html_safe, class: "mb-4 last:mb-0")
    end

    safe_join(formatted_paragraphs)
  end

  def post_status_badge_color(status)
    case status.to_s
    when "enqueued"
      :info
    when "published"
      :success
    when "failed"
      :danger
    when "rejected"
      :warning
    else
      :neutral
    end
  end

  private

  def auto_link_urls(text)
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

      result << ERB::Util.html_escape(text[last_end...match_start])

      escaped_url = ERB::Util.html_escape(url)
      result << %(<a href="#{escaped_url}" target="_blank" rel="noopener" class="font-medium text-brand underline underline-offset-4 transition hover:text-brand-hover">#{escaped_url}</a>)

      last_end = match_end
    end

    result << ERB::Util.html_escape(text[last_end..])
    result.join
  end
end
