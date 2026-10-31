module Normalizer
  module PageFetching
    def page_fetch_failures
      page_fetcher.failures
    end

    private

    def fetch_page(url)
      page_fetcher.fetch(url)
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
