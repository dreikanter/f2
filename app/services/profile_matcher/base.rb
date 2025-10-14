module ProfileMatcher
  # Base class for feed profile matchers
  #
  # Subclasses must implement the #match? method to determine if a feed
  # matches a specific profile based on URL and HTTP response.
  class Base
    attr_reader :url, :response

    # @param url [String] the feed URL
    # @param response [HttpClient::Response] the HTTP response object
    def initialize(url, response)
      @url = url
      @response = response
    end

    # Determines if the feed matches this profile
    # @return [Boolean] true if the feed matches this profile
    def match?
      raise NotImplementedError, "Subclasses must implement #match?"
    end
  end
end
