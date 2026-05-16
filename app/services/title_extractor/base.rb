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
  end
end
