require "faraday"
require "faraday/follow_redirects"
require "faraday/multipart"
require "net/http"
require_relative "base"

module HttpClient
  class FaradayAdapter < Base
    DEFAULT_OPTIONS = {
      timeout: 30,
      follow_redirects: true,
      max_redirects: 5
    }.freeze

    attr_reader :connection

    def initialize(options = {})
      @constructor_options = options.freeze
      @connection = build_default_connection
    end

    def default_options
      DEFAULT_OPTIONS.merge(@constructor_options)
    end

    def get(url, headers: {}, options: {})
      perform_request(:get, url, headers: headers, options: options)
    end

    def post(url, body: nil, headers: {}, options: {})
      perform_request(:post, url, body: body, headers: headers, options: options)
    end

    def put(url, body: nil, headers: {}, options: {})
      perform_request(:put, url, body: body, headers: headers, options: options)
    end

    def delete(url, headers: {}, options: {})
      perform_request(:delete, url, headers: headers, options: options)
    end

    private

    def perform_request(method, url, body: nil, headers: {}, options: {})
      # Merge default options with per-request options
      merged_options = DEFAULT_OPTIONS.merge(@constructor_options).merge(options)

      connection = build_connection_for_request(merged_options)

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
      default_options = DEFAULT_OPTIONS.merge(@constructor_options)
      build_connection(default_options)
    end

    def build_connection_for_request(options)
      # Use default connection if all settings match constructor defaults
      default_options = DEFAULT_OPTIONS.merge(@constructor_options)
      return @connection if options == default_options

      # Build custom connection for this request
      build_connection(options)
    end

    def build_connection(options)
      Faraday.new do |config|
        config.request :multipart
        config.options.timeout = options[:timeout]
        config.options.open_timeout = options[:timeout]

        if options[:follow_redirects]
          config.response :follow_redirects, limit: options[:max_redirects]
        end

        config.adapter Faraday.default_adapter
      end
    end
  end
end
