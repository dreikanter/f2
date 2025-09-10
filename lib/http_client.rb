# HTTP Client abstraction layer
#
# Provides a standardized interface over HTTP libraries (currently Faraday).
# This abstraction allows swapping HTTP implementations (Faraday -> Net::HTTP, HTTParty, etc.)
# without changing application code, and ensures consistent error handling across the app.
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

  class Base
    def get(url, headers: {}, options: {})
      raise NotImplementedError, "Subclasses must implement #get"
    end

    def post(url, body: nil, headers: {}, options: {})
      raise NotImplementedError, "Subclasses must implement #post"
    end

    def put(url, body: nil, headers: {}, options: {})
      raise NotImplementedError, "Subclasses must implement #put"
    end

    def delete(url, headers: {}, options: {})
      raise NotImplementedError, "Subclasses must implement #delete"
    end
  end
end
