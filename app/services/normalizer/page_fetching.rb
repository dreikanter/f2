module Normalizer
  module PageFetching
    private

    def fetch_page(url)
      result = PageFetcher.new.fetch(url)

      if result.failure
        Rails.logger.warn(message: "Page fetch failed", payload: page_fetch_context.merge(result.failure))
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
