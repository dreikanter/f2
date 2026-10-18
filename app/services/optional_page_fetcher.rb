# Adapts failed downloads to missing supplementary content.
class OptionalPageFetcher
  def initialize(fetcher: PageFetcher.new, on_error: nil)
    @fetcher = fetcher
    @on_error = on_error
  end

  def fetch(url)
    @fetcher.fetch(url)
  rescue PageFetcher::Error => e
    Rails.logger.warn(message: "Page fetch failed", payload: e.details.merge(message: e.message))
    original = e.original_error
    if original && !original.is_a?(HttpClient::TimeoutError) && !original.is_a?(HttpClient::ConnectionError)
      Rails.error.report(original, severity: :warning, context: e.details)
    end

    @on_error&.call(e)
    nil
  end
end
