class FeedRefreshJob < ApplicationJob
  queue_as :default

  # @param feed_id [Integer] ID of the feed to refresh
  # @param manual [Boolean] a user-initiated refresh forces through the digest
  #   cadence skip; scheduled runs (the default) may skip a redundant same-period
  #   digest before any LLM call.
  def perform(feed_id, manual: false)
    feed = Feed.find_by(id: feed_id)
    return unless feed

    Feed.with_advisory_lock!("feed_refresh_#{feed.id}", timeout_seconds: 0) do
      FeedRefreshWorkflow.new(feed, manual: manual).execute
    end
  rescue Loader::Error => e
    # Loader errors reflect the remote feed's health (HTTP 404/500, timeouts,
    # connection failures), not a bug on our side. They're already logged,
    # metered, and tracked as feed failures by the workflow, so we don't report
    # them to the error tracker — doing so just turns every dead or unreachable
    # feed into noise.
    Rails.logger.error "Feed #{feed_id} load failed: #{e.message}"
    Metrics.increment("loader_errors_total", profile: feed.feed_profile_key, loader: feed.loader_class.name.demodulize)
  rescue WithAdvisoryLock::FailedToAcquireLock
    Rails.logger.info "Feed #{feed_id} is already being processed, skipping"
  end
end
