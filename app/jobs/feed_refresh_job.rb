class FeedRefreshJob < ApplicationJob
  queue_as :default

  # @param feed_id [Integer] ID of the feed to refresh
  def perform(feed_id)
    feed = Feed.find_by(id: feed_id)
    return unless feed

    Feed.with_advisory_lock!("feed_refresh_#{feed.id}", timeout_seconds: 0) do
      Rails.error.handle(Loader::Error, context: { feed_id: feed.id }) do
        FeedRefreshWorkflow.new(feed).execute
      end
    end
  rescue WithAdvisoryLock::FailedToAcquireLock
    Rails.logger.info "Feed #{feed_id} is already being processed, skipping"
  end
end
