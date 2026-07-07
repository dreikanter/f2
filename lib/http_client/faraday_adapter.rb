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
      super(DEFAULT_OPTIONS.merge(options))
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
      validate_url = options.fetch(:validate_url, self.options[:validate_url])
      ensure_public_url!(url, validate_url) if validate_url

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
      validate_url = request_options.fetch(:validate_url, options[:validate_url])

      Faraday.new do |config|
        config.request :multipart
        config.options.timeout = timeout
        config.options.open_timeout = timeout

        if follow_redirects
          redirect_options = { limit: max_redirects }
          redirect_options[:callback] = redirect_guard(validate_url) if validate_url
          config.response :follow_redirects, **redirect_options
        end

        config.adapter Faraday.default_adapter
      end
    end

    # In public-only mode a caller passes a `validate_url` callable (typically
    # PublicUrl.method(:safe?)). We check the initial URL and, via the redirect
    # callback below, every hop — because follow_redirects otherwise chases a
    # public URL's 302 straight to a private/loopback/metadata address, past the
    # caller's one-time check (SSRF; spec 005 §8).
    def ensure_public_url!(url, validate_url)
      raise BlockedUrlError, "Blocked non-public URL: #{url}" unless validate_url.call(url.to_s)
    end

    def redirect_guard(validate_url)
      lambda do |_response_env, new_request_env|
        target = new_request_env.url.to_s
        raise BlockedUrlError, "Blocked non-public redirect to #{target}" unless validate_url.call(target)
      end
    end
  end
end
