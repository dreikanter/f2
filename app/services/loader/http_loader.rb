module Loader
  class HttpLoader < Base
    DEFAULT_MAX_REDIRECTS = 3

    def load
      response = http_client.get(feed.url)

      unless response.success?
        raise StandardError, "HTTP #{response.status}"
      end

      response.body
    rescue HttpClient::Error => e
      raise StandardError, e.message
    end

    private

    def http_client
      @http_client ||= options.fetch(:http_client) { default_http_client }
    end

    def default_http_client
      max_redirects = options.fetch(:max_redirects, DEFAULT_MAX_REDIRECTS)
      HttpClient.build(max_redirects: max_redirects)
    end
  end
end
