class PageFetcher
  def initialize(context: {})
    @context = context
  end

  # @param url [String, nil] supplementary page URL
  # @return [String, nil] response body, or nil when unavailable
  def fetch(url)
    return nil if url.blank?

    response = HttpClient.build(validate_url: PublicUrl.method(:safe?), pin_public_address: true).get(url)
    return response.body if response.success?

    details = context.merge(url: url).map { |key, value| "#{key}=#{value}" }.join(" ")
    Rails.logger.warn("Page fetch failed (HTTP #{response.status}) [#{details}]")
    nil
  rescue HttpClient::Error => e
    Rails.error.report(e, severity: :warning, context: context.merge(url: url))
    nil
  end

  private

  attr_reader :context
end
