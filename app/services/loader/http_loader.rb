module Loader
  class HttpLoader < Base
    def load
      response = http_get(feed_url)

      unless response.success?
        raise Loader::Error, "HTTP #{response.status}"
      end

      response.body
    end

    private

    def feed_url
      feed.url
    end
  end
end
