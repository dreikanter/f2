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
    # External search remains paused until its separate integration.
    return if FeedProfile.depends_on_ai?(feed.feed_profile_key) && feed.search_credential.present?

    Feed.with_advisory_lock!("feed_refresh_#{feed.id}", timeout_seconds: 0) do
      FeedRefreshWorkflow.new(feed, manual: manual).execute
    end
  rescue Loader::Error => e
    # Ordinary loader errors reflect the remote feed's health and are already
    # tracked by the workflow. AI errors retain their provider cause for the
    # error tracker; events only receive the loader's safe message.
    Rails.logger.error "Feed #{feed_id} load failed: #{e.message}"
    Rails.error.report(e) if FeedProfile.depends_on_ai?(feed.feed_profile_key)
    Metrics.increment("loader_errors_total", profile: feed.feed_profile_key, loader: feed.loader_class.name.demodulize)
  rescue WithAdvisoryLock::FailedToAcquireLock
    Rails.logger.info "Feed #{feed_id} is already being processed, skipping"
  end
end
