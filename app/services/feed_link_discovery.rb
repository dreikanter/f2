# Extracts the feed URLs a page advertises via typed alternate links
# (RSS, Atom, JSON Feed). Relative hrefs resolve against base_url, the
# final URL after redirects. The hrefs are author-controlled, so non-public
# URLs are dropped (SSRF). Returns at most LIMIT URLs, deduplicated, in
# document order; sites conventionally list the main feed first.
class FeedLinkDiscovery
  FEED_MIME_TYPES = %w[application/rss+xml application/atom+xml application/feed+json].freeze
  LIMIT = 3

  def self.call(html, base_url:)
    new(html, base_url: base_url).call
  end

  def initialize(html, base_url:)
    @html = html
    @base_url = base_url
  end

  def call
    return [] if @html.blank? || @base_url.blank?

    Nokogiri::HTML(@html)
      .css("link")
      .filter_map { |link| feed_url(link) }
      .uniq
      .select { |url| PublicUrl.safe?(url) }
      .first(LIMIT)
  end

  private

  def feed_url(link)
    return nil unless alternate_feed_link?(link)

    href = link["href"].to_s.strip
    return nil if href.empty?

    URI.join(@base_url, href).to_s
  rescue URI::Error
    nil
  end

  # rel is a space-separated token list; type may carry parameters
  # ("application/rss+xml; charset=utf-8").
  def alternate_feed_link?(link)
    rel_tokens = link["rel"].to_s.downcase.split
    type = link["type"].to_s.downcase.split(";").first.to_s.strip

    rel_tokens.include?("alternate") && FEED_MIME_TYPES.include?(type)
  end
end
