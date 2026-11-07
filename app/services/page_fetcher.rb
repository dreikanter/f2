class PageFetcher
  Result = Data.define(:body, :failure)

  # Expected external failures are data. Unexpected errors propagate to the
  # caller's error boundary; fetching never logs or reports them itself.
  #
  # @param url [String, nil] supplementary page URL
  # @return [Result] response body or failure details
  def fetch(url)
    return Result.new(body: nil, failure: nil) if url.blank?

    response = HttpClient.build.get(url)
    return Result.new(body: response.body, failure: nil) if response.success?

    failure(url, status: response.status, message: "HTTP #{response.status}",
                 retryable: [408, 429].include?(response.status) || (500..599).cover?(response.status))
  rescue HttpClient::TimeoutError, HttpClient::ConnectionError, HttpClient::SSLError => e
    failure(url, error_class: e.class.name, message: e.message, retryable: true)
  rescue HttpClient::TooManyRedirectsError, HttpClient::BlockedUrlError => e
    failure(url, error_class: e.class.name, message: e.message, retryable: false)
  end

  private

  def failure(url, **details)
    Result.new(body: nil, failure: { url: url, **details })
  end
end
