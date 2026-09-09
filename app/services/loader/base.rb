module Loader
  # Base class for feed loaders
  class Base
    DEFAULT_MAX_REDIRECTS = 3

    # @param feed [Feed] the feed to load from
    # @param options [Hash] optional configuration
    def initialize(feed, options = {})
      @feed = feed
      @options = options
    end

    # Loads raw data from feed source
    # @return [String] raw feed data
    # @abstract Subclasses must implement this method
    def load
      raise NotImplementedError, "Subclasses must implement #load method"
    end

    private

    attr_reader :feed, :options

    def http_get(url, **request_options)
      http_client.get(url, **request_options)
    rescue HttpClient::Error => e
      raise Loader::Error, e.message
    end

    def http_client
      @http_client ||= options.fetch(:http_client) do
        HttpClient.build(max_redirects: options.fetch(:max_redirects, DEFAULT_MAX_REDIRECTS))
      end
    end
  end
end
