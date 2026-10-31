module Normalizer
  module PageFetching
    def diagnostics
      page_fetch_failures.map do |failure|
        Diagnostic.new(message: "Supplementary page unavailable", details: failure.deep_dup.freeze)
      end.freeze
    end

    private

    def page_fetch_failures
      @page_fetch_failures ||= []
    end

    def fetch_page(url)
      result = PageFetcher.new.fetch(url)

      if result.failure
        failure = page_fetch_context.merge(result.failure)
        page_fetch_failures << failure
        Rails.logger.warn(message: "Page fetch failed", payload: failure)
      end

      result.body
    end

    def page_fetch_context
      {
        normalizer: self.class.name,
        feed_id: feed_entry.feed_id,
        uid: feed_entry.uid
      }
    end
  end
end
