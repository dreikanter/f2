require "faraday"
require "faraday/follow_redirects"
require "net/http"
require_relative "../http_client"

module HttpClient
  class FaradayAdapter < Base
    DEFAULT_TIMEOUT = 30

    attr_reader :timeout, :connection

    def initialize(timeout: DEFAULT_TIMEOUT)
      @timeout = timeout

      @connection = Faraday.new do |config|
        config.options.timeout = timeout
        config.options.open_timeout = timeout
        config.response :follow_redirects
        config.adapter Faraday.default_adapter
      end
    end

    def get(url, headers: {}, follow_redirects: true)
      perform_request(:get, url, headers: headers, follow_redirects: follow_redirects)
    end

    def post(url, body: nil, headers: {}, follow_redirects: true)
      perform_request(:post, url, body: body, headers: headers, follow_redirects: follow_redirects)
    end

    def put(url, body: nil, headers: {}, follow_redirects: true)
      perform_request(:put, url, body: body, headers: headers, follow_redirects: follow_redirects)
    end

    def delete(url, headers: {}, follow_redirects: true)
      perform_request(:delete, url, headers: headers, follow_redirects: follow_redirects)
    end

    private

    def perform_request(method, url, body: nil, headers: {}, follow_redirects: true)
      connection = build_connection_for_request(follow_redirects)
      
      response = connection.send(method) do |request|
        request.url url
        request.body = body if body
        headers.each { |key, value| request[key] = value }
      end

      Response.new(
        status: response.status,
        body: response.body,
        headers: response.headers.to_hash
      )
    rescue Faraday::TimeoutError, Timeout::Error => e
      raise TimeoutError, "Request timed out: #{e.message}"
    rescue Faraday::ConnectionFailed, SocketError, Errno::ECONNREFUSED, Errno::EHOSTUNREACH => e
      raise ConnectionError, "Connection failed: #{e.message}"
    rescue Faraday::Error => e
      raise Error, "HTTP error: #{e.message}"
    end

    def build_connection_for_request(follow_redirects)
      return @connection if follow_redirects

      Faraday.new do |config|
        config.options.timeout = @timeout
        config.options.open_timeout = @timeout
        config.adapter Faraday.default_adapter
      end
    end
  end
end
