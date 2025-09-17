# Event model for tracking feed refresh workflow statistics and errors
class FeedRefreshEvent
  # Creates a workflow statistics event
  # @param feed [Feed] the feed being processed
  # @param stats [Hash] workflow statistics
  # @return [Event] created event record
  def self.create_stats(feed, stats = {})
    Event.create!(
      type: "feed_refresh_stats",
      level: :info,
      subject: feed,
      user: feed.user,
      message: "Feed refresh completed for #{feed.name}",
      metadata: stats
    )
  end

  # Creates a workflow error event
  # @param feed [Feed] the feed being processed
  # @param error [StandardError] the error that occurred
  # @param stage [String] the workflow stage where error occurred
  # @param stats [Hash] partial statistics collected before error
  # @return [Event] created event record
  def self.create_error(feed, error, stage, stats = {})
    Event.create!(
      type: "feed_refresh_error",
      level: :error,
      subject: feed,
      user: feed.user,
      message: "Feed refresh failed at #{stage}: #{error.message}",
      metadata: stats.merge(
        error_class: error.class.name,
        error_message: error.message,
        error_stage: stage,
        error_backtrace: error.backtrace&.first(10)
      )
    )
  end

  # Creates an empty statistics hash with default values
  # @return [Hash] default statistics structure
  def self.default_stats
    {
      # Workflow timing
      total_duration: 0.0,
      load_duration: 0.0,
      process_duration: 0.0,
      normalize_duration: 0.0,

      # Content metrics
      content_size: 0,
      total_entries: 0,
      new_entries: 0,
      new_posts: 0,
      invalid_posts: 0,

      # Timestamps
      started_at: Time.current.iso8601,
      completed_at: nil
    }
  end
end