class FeedRefreshJob < ApplicationJob
  queue_as :default

  # @param feed_id [Integer] ID of the feed to refresh
  def perform(feed_id)
    feed = Feed.find(feed_id)

    # Use advisory lock to prevent concurrent processing of same feed
    Feed.with_advisory_lock("feed_refresh_#{feed.id}", timeout_seconds: 0) do
      refresh_feed(feed)
    end
  rescue WithAdvisoryLock::FailedToAcquireLock
    Rails.logger.info "Feed #{feed_id} is already being processed, skipping"
  rescue ActiveRecord::RecordNotFound
    Rails.logger.error "Feed #{feed_id} not found"
  rescue StandardError => e
    Rails.logger.error "Feed refresh failed for feed #{feed_id}: #{e.message}"
    raise
  end

  private

  # @param feed [Feed] the feed to refresh
  def refresh_feed(feed)
    stats = FeedRefreshEvent.default_stats
    total_start = Time.current

    begin
      Rails.logger.info "Starting feed refresh for feed #{feed.id}"

      # Step 1: Load feed contents
      load_start = Time.current
      raw_data = load_feed_contents(feed)
      stats[:load_duration] = Time.current - load_start
      stats[:content_size] = raw_data.bytesize

      # Step 2: Process feed contents into structured entries
      process_start = Time.current
      processed_entries = process_feed_contents(feed, raw_data)
      stats[:process_duration] = Time.current - process_start
      stats[:total_entries] = processed_entries.size

      # Step 3: Persist feed entries and get new ones
      new_feed_entries = persist_feed_entries(feed, processed_entries)
      stats[:new_entries] = new_feed_entries.size

      # Step 4: Normalize each new feed entry into posts
      normalize_start = Time.current
      normalize_results = normalize_feed_entries(new_feed_entries)
      stats[:normalize_duration] = Time.current - normalize_start
      stats[:new_posts] = normalize_results[:valid_posts]
      stats[:invalid_posts] = normalize_results[:invalid_posts]

      # Complete statistics
      stats[:total_duration] = Time.current - total_start
      stats[:completed_at] = Time.current.iso8601

      # Create success event
      FeedRefreshEvent.create_stats(feed, stats)

      Rails.logger.info "Feed refresh completed for feed #{feed.id}, processed #{new_feed_entries.count} new entries"

    rescue StandardError => e
      # Calculate partial duration
      stats[:total_duration] = Time.current - total_start

      # Create error event with partial stats
      stage = determine_error_stage(e, stats)
      FeedRefreshEvent.create_error(feed, e, stage, stats)

      raise
    end
  end

  # @param feed [Feed] the feed to load
  # @return [String] raw feed data
  def load_feed_contents(feed)
    feed.loader_instance.load
  end

  # @param feed [Feed] the feed being processed
  # @param raw_data [String] raw feed data
  # @return [Array<Hash>] processed feed entries with normalized keys
  def process_feed_contents(feed, raw_data)
    entries = feed.processor_instance(raw_data).process
    normalize_entry_keys(entries)
  end

  # @param feed [Feed] the feed to persist entries for
  # @param processed_entries [Array<Hash>] processed feed entries
  # @return [Array<FeedEntry>] newly created feed entries
  def persist_feed_entries(feed, processed_entries)
    new_entries = []

    processed_entries.each do |entry_data|
      uid = entry_data[:uid]
      next unless uid.present?

      # Check if entry already exists to avoid duplication
      existing_entry = feed.feed_entries.find_by(uid: uid)
      next if existing_entry

      # Create new feed entry
      feed_entry = feed.feed_entries.create!(
        uid: uid,
        published_at: entry_data[:published_at],
        raw_data: entry_data[:raw_data] || entry_data,
        status: :pending
      )

      new_entries << feed_entry
    end

    new_entries
  end

  # @param feed_entries [Array<FeedEntry>] feed entries to normalize
  # @return [Hash] normalization results with counts
  def normalize_feed_entries(feed_entries)
    return { valid_posts: 0, invalid_posts: 0 } if feed_entries.empty?

    feed = feed_entries.first.feed
    valid_posts = 0
    invalid_posts = 0

    feed_entries.each do |feed_entry|
      result = normalize_single_entry(feed_entry, feed)
      if result[:valid]
        valid_posts += 1
      else
        invalid_posts += 1
      end
    end

    { valid_posts: valid_posts, invalid_posts: invalid_posts }
  end

  # @param feed_entry [FeedEntry] the feed entry to normalize
  # @param feed [Feed] the feed (for creating normalizer instance)
  # @return [Hash] result with validity status
  def normalize_single_entry(feed_entry, feed)
    normalizer = feed.normalizer_instance(feed_entry)
    post = normalizer.normalize

    # Mark feed entry as processed regardless of post validity
    feed_entry.update!(status: :processed)

    # Return whether the post is valid (enqueued) or invalid (rejected)
    { valid: post.status == "enqueued" }
  rescue StandardError => e
    Rails.logger.error "Failed to normalize feed entry #{feed_entry.id}: #{e.message}"
    feed_entry.update!(status: :processed)
    { valid: false }
  end

  # Normalizes entry data keys to symbols
  # @param entries [Array<Hash>] processed entries with mixed key types
  # @return [Array<Hash>] entries with normalized symbol keys
  def normalize_entry_keys(entries)
    entries.map do |entry|
      {
        uid: entry[:uid] || entry["uid"],
        published_at: entry[:published_at] || entry["published_at"],
        raw_data: entry[:raw_data] || entry["raw_data"]
      }
    end
  end

  # Determines the workflow stage where an error occurred based on statistics
  # @param error [StandardError] the error that occurred
  # @param stats [Hash] current statistics
  # @return [String] the workflow stage name
  def determine_error_stage(error, stats)
    if stats[:load_duration] == 0.0
      "loading"
    elsif stats[:process_duration] == 0.0
      "processing"
    elsif stats[:normalize_duration] == 0.0
      "normalizing"
    else
      "completing"
    end
  end
end
