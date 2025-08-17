class FeedRefreshJob < ApplicationJob
  queue_as :default

  def perform(feed_id)
    feed = Feed.find_by(id: feed_id)
    return unless feed

    # TODO: Implement actual feed fetching logic
    Rails.logger.info "Refreshing feed: #{feed.name} (#{feed.url})"

    # Future implementation will:
    # 1. Use feed.loader to fetch data from feed.url
    # 2. Use feed.processor to parse the data format
    # 3. Use feed.normalizer to transform data to standard format
    # 4. Store the normalized data entities
  end
end
