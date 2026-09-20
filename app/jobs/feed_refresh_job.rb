class FeedRefreshJob < ApplicationJob
  queue_as :default

  # @param feed_id [Integer] ID of the feed to refresh
  # @param manual [Boolean] a user-initiated refresh forces through the
  #   digest cadence skip; scheduled runs may skip a redundant same-period
  #   digest.
  def perform(feed_id, manual: false)
    feed = Feed.find_by(id: feed_id)
    return unless feed

    # Webhook feeds have no loader to run; drop stray kicks.
    return if feed.feed_profile_key == "webhook"

    Feed.with_advisory_lock!("feed_refresh_#{feed.id}", timeout_seconds: 0) do
      FeedRefreshWorkflow.new(feed, manual: manual).execute
    end
  rescue Loader::ExecutionLimitExceeded
    nil
  rescue Loader::Error => e
    Rails.error.report(e, context: { feed_id: feed_id })
    Metrics.increment("loader_errors_total", profile: feed.feed_profile_key, loader: feed.loader_class.name.demodulize)
  rescue LlmResult::LifecycleError => e
    Rails.error.report(e, context: { feed_id: feed_id })
    Metrics.increment("processor_errors_total", profile: feed.feed_profile_key, processor: feed.processor_class.name.demodulize)
  rescue WithAdvisoryLock::FailedToAcquireLock
    Rails.logger.info "Feed #{feed_id} is already being processed, skipping"
  end
end
