class PageFetcher
  attr_reader :failures

  def initialize(context: {})
    @context = context
    @failures = []
  end

  # @param url [String, nil] supplementary page URL
  # @param required [Boolean] whether the post needs this page's content
  # @return [String, nil] response body, or nil when unavailable
  def fetch(url, required: false)
    return nil if url.blank?

    response = HttpClient.build.get(url)
    return response.body if response.success?

    details = context.merge(url: url).map { |key, value| "#{key}=#{value}" }.join(" ")
    Rails.logger.warn("Page fetch failed (HTTP #{response.status}) [#{details}]")
    record_failure(url, required: required, retryable: retryable_status?(response.status),
                        status: response.status, message: "HTTP #{response.status}")
    nil
  rescue HttpClient::TimeoutError, HttpClient::ConnectionError => e
    Rails.logger.warn(
      message: "Page fetch failed",
      payload: context.merge(url: url, error_class: e.class.name)
    )
    record_failure(url, required: required, retryable: true, error_class: e.class.name, message: e.message)
    nil
  rescue HttpClient::Error => e
    Rails.error.report(e, severity: :warning, context: context.merge(url: url))
    record_failure(url, required: required, retryable: false, error_class: e.class.name, message: e.message)
    nil
  end

  private

  attr_reader :context

  def record_failure(url, **details)
    failures << context.merge(url: url, **details)
  end

  def retryable_status?(status)
    [408, 429].include?(status) || (500..599).cover?(status)
  end
end
