# Finds the feeds a web page advertises: typed alternate links in its markup
# (application/rss+xml, application/atom+xml, application/feed+json), resolved
# against the URL the page was fetched from — the final one after redirects,
# so relative hrefs point where the page actually lives.
#
# This feeds the identification fallback for page URLs (#1290): when a pasted
# link matches no profile directly, these are the URLs worth checking next.
#
# Page authors control the hrefs, so every resolved URL passes the PublicUrl
# SSRF guard before being offered for fetching (redirect hops stay the fetch
# layer's concern, #920). Returns at most LIMIT URLs, deduplicated, in
# document order — sites conventionally list the main feed before auxiliary
# ones like comment feeds.
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

  # rel is a space-separated token list, and type may carry parameters
  # ("application/rss+xml; charset=utf-8"); both compare case-insensitively.
  def alternate_feed_link?(link)
    rel_tokens = link["rel"].to_s.downcase.split
    type = link["type"].to_s.downcase.split(";").first.to_s.strip

    rel_tokens.include?("alternate") && FEED_MIME_TYPES.include?(type)
  end
end
