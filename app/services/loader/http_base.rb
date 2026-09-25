module Loader
  class HttpBase < Base
    class TransportError < Loader::Error; end

    DEFAULT_MAX_REDIRECTS = 3

    private

    def http_get(url, **request_options)
      http_client.get(url, **request_options)
    rescue HttpClient::TimeoutError, HttpClient::ConnectionError => e
      log_transport_error(url, e)
      raise TransportError, e.message
    rescue HttpClient::Error => e
      raise Loader::Error, e.message
    end

    def log_transport_error(url, error)
      uri = URI.parse(url.to_s)
      Rails.logger.warn(
        message: "Feed source request failed",
        payload: {
          feed_id: feed.id,
          profile: feed.feed_profile_key,
          loader: self.class.name,
          host: uri.host,
          path: uri.path,
          error_class: error.class.name
        }
      )
    end

    def http_client
      @http_client ||= options.fetch(:http_client) do
        HttpClient.build(max_redirects: options.fetch(:max_redirects, DEFAULT_MAX_REDIRECTS))
      end
    end
  end
end
