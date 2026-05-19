module ProfileMatcher
  # Universal URL fallback. Matches any URL the user pastes and offers
  # AI extraction. Lowest specificity, so it always ranks below
  # structured matchers (RSS, XKCD, …) for the same URL.
  class LlmWebsiteExtractorMatcher < Base
    input_shape :url
    match_specificity 1
    depends_on_ai true

    def self.profile_key
      "llm_website_extractor"
    end

    def match?
      return false if input.blank?

      URI.parse(input).is_a?(URI::HTTP)
    rescue URI::InvalidURIError
      false
    end
  end
end
