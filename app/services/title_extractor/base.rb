module TitleExtractor
  # Base class for feed title extractors.
  #
  # Constructor takes the same shape as ProfileMatcher::Base —
  # (input, fetched_body) — so the detector can share one call shape
  # across matchers and title extractors.
  class Base
    attr_reader :input, :fetched_body

    # @param input [String] the user's raw input (URL today)
    # @param fetched_body [String, nil] the body of the URL when applicable
    def initialize(input, fetched_body = nil)
      @input = input
      @fetched_body = fetched_body
    end

    # Extracts the feed title
    # @return [String, nil] the feed title or nil if it cannot be extracted
    def title
      raise NotImplementedError, "Subclasses must implement #title"
    end

    protected

    def hostname_from_url
      host = URI.parse(input.to_s).host.to_s.sub(/\Awww\./, "")
      host.presence
    rescue URI::InvalidURIError
      nil
    end

    # og:title of the fetched page, for sources whose profile URL resolves to
    # HTML rather than a feed. Any parse trouble means "no title here" — the
    # caller falls back to a handle derived from the input.
    def og_title
      return nil if fetched_body.blank?

      doc = Nokogiri::HTML.parse(fetched_body, nil, "UTF-8")
      doc.at_css('meta[property="og:title"]')&.[]("content")&.strip
    rescue StandardError
      nil
    end
  end
end
