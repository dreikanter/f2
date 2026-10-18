module Normalizer
  module PageFetching
    private

    def fetch_page(url)
      @page_fetcher ||= PageFetcher.new(context: {
        normalizer: self.class.name, feed_id: feed_entry.feed_id, uid: feed_entry.uid
      })

      @page_fetcher.fetch(url)
    end
  end
end
