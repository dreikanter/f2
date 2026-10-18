class PageFetcher
  class Error < StandardError
    attr_reader :url, :status, :original_error

    def initialize(url:, status: nil, original_error: nil)
      @url = url
      @status = status
      @original_error = original_error
      super(original_error ? original_error.message : "HTTP #{status}")
    end

    def details
      { url: url, status: status, error_class: original_error&.class&.name }.compact
    end
  end

  # @param url [String, nil] supplementary page URL
  # @return [String, nil] response body, or nil for a blank URL
  # @raise [Error] when the page cannot be downloaded
  def fetch(url)
    return nil if url.blank?

    response = HttpClient.build.get(url)
    return response.body if response.success?

    raise Error.new(url: url, status: response.status)
  rescue HttpClient::Error => e
    raise Error.new(url: url, original_error: e)
  end
end
