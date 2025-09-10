module HttpClient
  class Response
    attr_reader :status, :body, :headers

    def initialize(status:, body:, headers: {})
      @status = status
      @body = body
      @headers = headers
    end

    def success?
      (200..299).include?(status)
    end
  end

  class Error < StandardError; end
  class ConnectionError < Error; end
  class TimeoutError < Error; end

  class Base
    def get(url, headers: {})
      raise NotImplementedError, "Subclasses must implement #get"
    end

    def post(url, body: nil, headers: {})
      raise NotImplementedError, "Subclasses must implement #post"
    end

    def put(url, body: nil, headers: {})
      raise NotImplementedError, "Subclasses must implement #put"
    end

    def delete(url, headers: {})
      raise NotImplementedError, "Subclasses must implement #delete"
    end
  end
end