require "faraday"
require_relative "../http_client"

module HttpClient
  class FaradayAdapter < Base
    DEFAULT_TIMEOUT = 30

    def initialize(timeout: DEFAULT_TIMEOUT)
      @timeout = timeout
      @connection = Faraday.new do |config|
        config.options.timeout = timeout
        config.options.open_timeout = timeout
        config.adapter Faraday.default_adapter
      end
    end

    def get(url, headers: {})
      perform_request(:get, url, headers: headers)
    end

    def post(url, body: nil, headers: {})
      perform_request(:post, url, body: body, headers: headers)
    end

    def put(url, body: nil, headers: {})
      perform_request(:put, url, body: body, headers: headers)
    end

    def delete(url, headers: {})
      perform_request(:delete, url, headers: headers)
    end

    private

    def perform_request(method, url, body: nil, headers: {})
      response = @connection.send(method) do |request|
        request.url url
        request.body = body if body
        headers.each { |key, value| request[key] = value }
      end

      Response.new(
        status: response.status,
        body: response.body,
        headers: response.headers.to_hash
      )
    rescue Faraday::ConnectionFailed => e
      raise ConnectionError, "Connection failed: #{e.message}"
    rescue Faraday::TimeoutError => e
      raise TimeoutError, "Request timed out: #{e.message}"
    rescue Faraday::Error => e
      raise Error, "HTTP error: #{e.message}"
    end
  end
end