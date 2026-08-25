# HTTP Client abstraction layer
#
# Provides a standardized interface over HTTP libraries (currently Faraday).
# This abstraction allows swapping HTTP implementations (Faraday -> Net::HTTP,
# HTTParty, etc.) without changing application code, and ensures consistent error
# handling across the app.
#
require_relative "http_client/base"
require_relative "http_client/faraday_adapter"
require_relative "http_client/caching_adapter"

module HttpClient
  class Response
    attr_reader :status, :body, :headers, :url

    # `url` is the final URL the response came from — after redirects, it names
    # the landing URL rather than the requested one, so relative references in
    # the body can be resolved against the right base. nil when the adapter
    # doesn't track it (e.g. hand-built responses in tests).
    def initialize(status:, body:, headers: {}, url: nil)
      @status = status
      @body = body
      @headers = headers
      @url = url
    end

    def success?
      status >= 200 && status < 300
    end
  end

  class Error < StandardError; end
  class ConnectionError < Error; end
  class TimeoutError < Error; end
  class TooManyRedirectsError < Error; end
  # Raised in public-only mode when the initial URL or any redirect hop is not a
  # public host (SSRF guard; see FaradayAdapter#ensure_public_url!).
  class BlockedUrlError < Error; end

  def self.build(options = {})
    adapter_class = options.delete(:adapter) || default_adapter_class
    adapter_class.new(**options)
  end

  def self.default_adapter_class
    FaradayAdapter
  end
end
