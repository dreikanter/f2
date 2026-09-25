module Loader
  class HttpBase < Base
    DEFAULT_MAX_REDIRECTS = 3

    private

    def http_get(url, **request_options)
      host = host_for(url)
      if host
        capacity = RateLimit.acquire(:web_fetch, subject: host, cost: {})
        unless capacity.allowed?
          raise Throttled.new(source_host: host, retry_after: capacity.retry_after)
        end
      end

      response = http_client.get(url, **request_options)
      if response.status == 429
        source_host = host_for(response.url) || host
        error = Throttled.from_response(response, source_host: source_host)
        # Remember both hosts so the redirecting URL also respects the cooldown.
        [host, source_host].compact.uniq.each do |subject|
          RateLimit.penalize(:web_fetch, subject: subject, retry_after: error.retry_after)
        end
        raise error
      end

      response
    rescue HttpClient::Error => e
      raise Loader::Error, e.message
    end

    def host_for(url)
      URI.parse(url.to_s).host&.downcase
    rescue URI::InvalidURIError
      nil
    end

    def http_client
      @http_client ||= options.fetch(:http_client) do
        HttpClient.build(max_redirects: options.fetch(:max_redirects, DEFAULT_MAX_REDIRECTS))
      end
    end
  end
end
