class FeedRefreshJob < ApplicationJob
  queue_as :default

  # @param feed_id [Integer] ID of the feed to refresh
  def perform(feed_id)
    feed = Feed.find_by(id: feed_id)
    return unless feed

    # Webhook feeds have no loader to run; drop stray kicks.
    return if feed.feed_profile_key == "webhook"

    Feed.with_advisory_lock!("feed_refresh_#{feed.id}", timeout_seconds: 0) do
      FeedRefreshWorkflow.new(feed).execute
    end
  rescue Loader::LlmLoader::ExecutionLimitExceeded
    record_loader_error(feed)
  rescue Loader::Error => e
    Rails.error.report(e, context: { feed_id: feed_id })
    record_loader_error(feed)
  rescue LlmResult::LifecycleError => e
    Rails.error.report(e, context: { feed_id: feed_id })
    Metrics.increment("processor_errors_total", profile: feed.feed_profile_key, processor: feed.processor_class.name.demodulize)
  rescue WithAdvisoryLock::FailedToAcquireLock
    Rails.logger.info "Feed #{feed_id} is already being processed, skipping"
  end

  private

  def record_loader_error(feed)
    Metrics.increment("loader_errors_total", profile: feed.feed_profile_key, loader: feed.loader_class.name.demodulize)
  end
end
