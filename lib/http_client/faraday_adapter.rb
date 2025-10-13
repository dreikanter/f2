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

    def initialize(**options)
      merged_options = DEFAULT_OPTIONS.merge(options)
      super(merged_options)
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
      connection = build_connection(options)

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

    def build_connection(request_options)
      timeout = request_options.fetch(:timeout, options[:timeout])
      follow_redirects = request_options.fetch(:follow_redirects, options[:follow_redirects])
      max_redirects = request_options.fetch(:max_redirects, options[:max_redirects])

      Faraday.new do |config|
        config.request :multipart
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
