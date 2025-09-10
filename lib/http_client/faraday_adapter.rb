require "faraday"
require "faraday/follow_redirects"
require "net/http"
require_relative "../http_client"

module HttpClient
  class FaradayAdapter < Base
    DEFAULT_TIMEOUT = 30
    DEFAULT_FOLLOW_REDIRECTS = true
    DEFAULT_MAX_REDIRECTS = 5

    attr_reader :timeout, :follow_redirects, :max_redirects, :connection

    def initialize(timeout: DEFAULT_TIMEOUT, follow_redirects: DEFAULT_FOLLOW_REDIRECTS, max_redirects: DEFAULT_MAX_REDIRECTS)
      @timeout = timeout
      @follow_redirects = follow_redirects
      @max_redirects = max_redirects

      @connection = build_default_connection
    end

    def get(url, headers: {}, follow_redirects: nil, max_redirects: nil, timeout: nil)
      perform_request(:get, url, headers: headers, follow_redirects: follow_redirects, max_redirects: max_redirects, timeout: timeout)
    end

    def post(url, body: nil, headers: {}, follow_redirects: nil, max_redirects: nil, timeout: nil)
      perform_request(:post, url, body: body, headers: headers, follow_redirects: follow_redirects, max_redirects: max_redirects, timeout: timeout)
    end

    def put(url, body: nil, headers: {}, follow_redirects: nil, max_redirects: nil, timeout: nil)
      perform_request(:put, url, body: body, headers: headers, follow_redirects: follow_redirects, max_redirects: max_redirects, timeout: timeout)
    end

    def delete(url, headers: {}, follow_redirects: nil, max_redirects: nil, timeout: nil)
      perform_request(:delete, url, headers: headers, follow_redirects: follow_redirects, max_redirects: max_redirects, timeout: timeout)
    end

    private

    def perform_request(method, url, body: nil, headers: {}, follow_redirects: nil, max_redirects: nil, timeout: nil)
      # Use constructor defaults when per-request values are nil
      effective_follow_redirects = follow_redirects.nil? ? @follow_redirects : follow_redirects
      effective_max_redirects = max_redirects.nil? ? @max_redirects : max_redirects
      effective_timeout = timeout.nil? ? @timeout : timeout

      connection = build_connection_for_request(effective_follow_redirects, effective_max_redirects, effective_timeout)

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
    rescue Faraday::FollowRedirects::RedirectLimitReached => e
      raise TooManyRedirectsError, "Too many redirects: #{e.message}"
    rescue Faraday::Error => e
      raise Error, "HTTP error: #{e.message}"
    end

    def build_default_connection
      Faraday.new do |config|
        config.options.timeout = @timeout
        config.options.open_timeout = @timeout
        if @follow_redirects
          config.response :follow_redirects, limit: @max_redirects
        end
        config.adapter Faraday.default_adapter
      end
    end

    def build_connection_for_request(follow_redirects, max_redirects, timeout)
      # Use default connection if all settings match constructor defaults
      if follow_redirects == @follow_redirects && max_redirects == @max_redirects && timeout == @timeout
        return @connection
      end

      # Build custom connection for this request
      Faraday.new do |config|
        config.options.timeout = timeout
        config.options.open_timeout = timeout
        if follow_redirects
          config.response :follow_redirects, limit: max_redirects
        end
        config.adapter Faraday.default_adapter
      end
    end
  end
end
