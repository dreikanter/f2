# HTTP Client abstraction layer
#
# Provides a standardized interface over HTTP libraries (currently Faraday).
# This abstraction allows swapping HTTP implementations (Faraday -> Net::HTTP,
# HTTParty, etc.) without changing application code, and ensures consistent error
# handling across the app.
#
require_relative "http_client/base"
require_relative "http_client/faraday_adapter"

module HttpClient
  class Response
    attr_reader :status, :body, :headers

    def initialize(status:, body:, headers: {})
      @status = status
      @body = body
      @headers = headers
    end

    def success?
      status >= 200 && status < 300
    end
  end

  class Error < StandardError; end
  class ConnectionError < Error; end
  class TimeoutError < Error; end
  class TooManyRedirectsError < Error; end

  def self.build(options = {})
    adapter_class = options.delete(:adapter) || default_adapter_class
    adapter_class.new(options)
  end

  def self.default_adapter_class
    FaradayAdapter
  end
end
