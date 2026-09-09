module Loader
  class HttpBase < Base
    DEFAULT_MAX_REDIRECTS = 3

    private

    def http_get(url, **request_options)
      http_client.get(url, **request_options)
    rescue HttpClient::Error => e
      raise Loader::Error, e.message
    end

    def http_client
      @http_client ||= options.fetch(:http_client) do
        HttpClient.build(max_redirects: options.fetch(:max_redirects, DEFAULT_MAX_REDIRECTS))
      end
    end
  end
end
