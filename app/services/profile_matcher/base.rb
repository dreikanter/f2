module ProfileMatcher
  # Base class for feed profile matchers
  #
  # Subclasses must implement the #match? method to determine if a feed
  # matches a specific profile based on URL and HTTP response.
  # Subclasses should also implement self.profile_key to return their profile identifier.
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

    # Returns the profile key for this matcher
    # Default implementation derives it from the class name (fallback for compatibility)
    # Subclasses should override this with an explicit profile key
    # @return [String] the profile key (e.g., "rss", "xkcd")
    def self.profile_key
      name.demodulize.gsub(/ProfileMatcher$/, "").underscore
    end
  end
end
