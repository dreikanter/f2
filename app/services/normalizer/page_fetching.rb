module Normalizer
  module PageFetching
    def page_fetch_failures
      page_fetcher.failures
    end

    def awaiting_content?
      page_fetch_failures.any? { |failure| failure[:required] && failure[:retryable] }
    end

    private

    def validate_content
      errors = super
      errors << "page_unavailable" if page_fetch_failures.any? { |failure| failure[:required] }
      errors
    end

    def fetch_page(url, required: false)
      page_fetcher.fetch(url, required: required)
    end

    def page_fetcher
      @page_fetcher ||= PageFetcher.new(
        context: {
          normalizer: self.class.name,
          feed_id: feed_entry.feed_id,
          uid: feed_entry.uid
        }
      )
    end
  end
end
