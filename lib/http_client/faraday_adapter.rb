require "faraday"
require "faraday/follow_redirects"
require "faraday/multipart"
require "net/http"
require "digest"
require_relative "base"

module HttpClient
  class FaradayAdapter < Base
    DEFAULT_OPTIONS = {
      timeout: 30,
      follow_redirects: true,
      max_redirects: 5,
      cache: false
    }.freeze

    CACHE_EXPIRATION = 10.minutes

    def initialize(**options)
      merged_options = DEFAULT_OPTIONS.merge(options)

      if merged_options[:cache]
        merged_options[:cache_key] ||= method(:default_cache_key)
        merged_options[:cache_read] ||= method(:default_cache_read)
        merged_options[:cache_write] ||= method(:default_cache_write)
      end

      super(merged_options)
    end

    def get(url, headers: {}, options: {})
      if self.options[:cache]
        cache_key = generate_cache_key(:get, url, headers, options)
        cached_response = read_from_cache(cache_key)
        return cached_response if cached_response

        response = perform_request(:get, url, headers: headers, options: options)
        write_to_cache(cache_key, response)
        response
      else
        perform_request(:get, url, headers: headers, options: options)
      end
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

    # Cache helper methods
    def generate_cache_key(method, url, headers, request_options)
      options[:cache_key].call(method, url, headers, request_options)
    end

    def read_from_cache(cache_key)
      options[:cache_read].call(cache_key)
    end

    def write_to_cache(cache_key, response)
      options[:cache_write].call(cache_key, response)
    end

    def default_cache_key(method, url, headers, request_options)
      "http_client:#{Digest::SHA256.hexdigest("#{method}:#{url}")}"
    end

    def default_cache_read(cache_key)
      cached_data = Rails.cache.read(cache_key)
      return nil unless cached_data

      Response.new(
        status: cached_data[:status],
        body: cached_data[:body],
        headers: cached_data[:headers]
      )
    end

    def default_cache_write(cache_key, response)
      Rails.cache.write(
        cache_key,
        { status: response.status, body: response.body, headers: response.headers },
        expires_in: CACHE_EXPIRATION
      )
    end
  end
end
