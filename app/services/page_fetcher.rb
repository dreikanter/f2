class PageFetcher
  attr_reader :failures

  def initialize(context: {})
    @context = context
    @failures = []
  end

  # @param url [String, nil] supplementary page URL
  # @return [String, nil] response body, or nil when unavailable
  def fetch(url)
    return nil if url.blank?

    response = HttpClient.build.get(url)
    return response.body if response.success?

    details = context.merge(url: url).map { |key, value| "#{key}=#{value}" }.join(" ")
    Rails.logger.warn("Page fetch failed (HTTP #{response.status}) [#{details}]")
    record_failure(url, status: response.status, message: "HTTP #{response.status}")
    nil
  rescue HttpClient::TimeoutError, HttpClient::ConnectionError => e
    Rails.logger.warn(
      message: "Page fetch failed",
      payload: context.merge(url: url, error_class: e.class.name)
    )
    record_failure(url, error_class: e.class.name, message: e.message)
    nil
  rescue HttpClient::Error => e
    Rails.error.report(e, severity: :warning, context: context.merge(url: url))
    record_failure(url, error_class: e.class.name, message: e.message)
    nil
  end

  private

  attr_reader :context

  def record_failure(url, **details)
    failures << context.merge(url: url, **details)
  end
end
