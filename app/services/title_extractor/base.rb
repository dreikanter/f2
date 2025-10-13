module TitleExtractor
  # Base class for feed title extractors
  #
  # Subclasses must implement the #title method to extract the feed title
  # from the URL and HTTP response.
  class Base
    attr_reader :url, :response

    # @param url [String] the feed URL
    # @param response [HttpClient::Response] the HTTP response object
    def initialize(url, response)
      @url = url
      @response = response
    end

    # Extracts the feed title
    # @return [String, nil] the feed title or nil if it cannot be extracted
    def title
      raise NotImplementedError, "Subclasses must implement #title"
    end
  end
end
