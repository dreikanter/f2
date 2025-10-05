# Event model for tracking feed refresh workflow statistics and errors
class FeedRefreshEvent
  # Creates a workflow statistics event
  # @param feed [Feed] the feed being processed
  # @param stats [Hash] workflow statistics
  # @return [Event] created event record
  def self.create_stats(feed:, stats: {})
    Event.create!(
      type: "FeedRefreshStats",
      level: :info,
      subject: feed,
      user: feed.user,
      message: "Feed refresh completed for #{feed.name}",
      metadata: { stats: stats }
    )
  end

  # Creates a workflow error event
  # @param feed [Feed] the feed being processed
  # @param error [StandardError] the error that occurred
  # @param stage [String] the workflow stage where error occurred
  # @param stats [Hash] partial statistics collected before error
  # @return [Event] created event record
  def self.create_error(feed:, error:, stage:, stats: {})
    Event.create!(
      type: "FeedRefreshError",
      level: :error,
      subject: feed,
      user: feed.user,
      message: "Feed refresh failed at #{stage}: #{error.message}",
      metadata: {
        stats: stats,
        error: {
          class: error.class.name,
          message: error.message,
          stage: stage,
          backtrace: error.backtrace
        }
      }
    )
  end
end
