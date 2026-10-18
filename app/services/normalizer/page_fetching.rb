module Normalizer
  module PageFetching
    private

    def fetch_page(url)
      PageFetcher.new.fetch(url)
    rescue PageFetcher::Error => e
      context = {
        normalizer: self.class.name,
        feed_id: feed_entry.feed_id,
        uid: feed_entry.uid,
        **e.details
      }

      Rails.logger.warn(message: "Page download failed", payload: context.merge(message: e.message))
      original = e.original_error
      if original && !original.is_a?(HttpClient::TimeoutError) && !original.is_a?(HttpClient::ConnectionError)
        Rails.error.report(original, severity: :warning, context: context)
      end

      if feed_entry.feed.persisted?
        Event.record!(
          type: "page_download_failed",
          level: :warning,
          subject: feed_entry.feed,
          user: feed_entry.feed.user,
          message: e.message,
          metadata: { stats: context }
        )
      end

      nil
    end
  end
end
