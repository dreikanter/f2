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

  class Base
    def get(url, headers: {}, follow_redirects: true, max_redirects: 5)
      raise NotImplementedError, "Subclasses must implement #get"
    end

    def post(url, body: nil, headers: {}, follow_redirects: true, max_redirects: 5)
      raise NotImplementedError, "Subclasses must implement #post"
    end

    def put(url, body: nil, headers: {}, follow_redirects: true, max_redirects: 5)
      raise NotImplementedError, "Subclasses must implement #put"
    end

    def delete(url, headers: {}, follow_redirects: true, max_redirects: 5)
      raise NotImplementedError, "Subclasses must implement #delete"
    end
  end
end
