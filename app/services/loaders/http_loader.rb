module Loaders
  class HttpLoader < Base
    DEFAULT_MAX_REDIRECTS = 3

    def load
      response = http_client.get(feed.url)

      if response.success?
        {
          status: :success,
          data: response.body,
          content_type: extract_content_type(response.headers)
        }
      else
        {
          status: :error,
          error: "HTTP #{response.status}",
          data: nil,
          content_type: nil
        }
      end
    rescue HttpClient::Error => e
      {
        status: :error,
        error: e.message,
        data: nil,
        content_type: nil
      }
    end

    private

    def http_client
      @http_client ||= options.fetch(:http_client) { default_http_client }
    end

    def default_http_client
      max_redirects = options.fetch(:max_redirects, DEFAULT_MAX_REDIRECTS)
      HttpClient::FaradayAdapter.new(max_redirects: max_redirects)
    end

    def extract_content_type(headers)
      content_type = headers["content-type"] || headers["Content-Type"] || headers[:content_type]
      return nil unless content_type

      # Extract main type, ignore charset and other parameters
      content_type.split(";").first&.strip
    end
  end
end
