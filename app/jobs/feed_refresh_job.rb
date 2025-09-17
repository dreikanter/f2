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
    @total_start = Time.current
    current_stage = "initializing"

    begin
      Rails.logger.info "Starting feed refresh for feed #{feed.id}"

      current_stage = "loading"
      raw_data = execute_loading_step(feed)

      current_stage = "processing"
      processed_entries = execute_processing_step(feed, raw_data)

      current_stage = "persisting"
      new_feed_entries = execute_persistence_step(feed, processed_entries)

      current_stage = "normalizing"
      execute_normalization_step(new_feed_entries)

      current_stage = "completing"
      finalize_stats

      # Create success event
      FeedRefreshEvent.create_stats(feed, stats)

      Rails.logger.info "Feed refresh completed for feed #{feed.id}, processed #{new_feed_entries.count} new entries"

    rescue StandardError => e
      # Create error event with explicit stage
      FeedRefreshEvent.create_error(feed, e, current_stage, finalize_stats)

      raise
    end
  end

  # @param feed [Feed] the feed to load
  # @return [String] raw feed data
  def load_feed_contents(feed)
    feed.loader_instance.load
  rescue ArgumentError => e
    # Re-raise ArgumentError as-is for invalid loader configurations
    raise
  rescue StandardError => e
    raise StandardError, "Failed to load feed from URL #{feed.url}: #{e.message}"
  end

  # @param feed [Feed] the feed being processed
  # @param raw_data [String] raw feed data
  # @return [Array<Hash>] processed feed entries with normalized keys
  def process_feed_contents(feed, raw_data)
    entries = feed.processor_instance(raw_data).process
    normalize_entry_keys(entries)
  rescue ArgumentError => e
    # Re-raise ArgumentError as-is for invalid processor configurations
    raise
  rescue StandardError => e
    content_preview = raw_data.truncate(100) if raw_data.respond_to?(:truncate)
    raise StandardError, "Failed to process feed content (#{raw_data.bytesize} bytes, preview: '#{content_preview}'): #{e.message}"
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

    feed_entries.each_with_index do |feed_entry, index|
      begin
        result = normalize_single_entry(feed_entry, feed)
        if result[:valid]
          valid_posts += 1
        else
          invalid_posts += 1
        end
      rescue StandardError => e
        # Re-raise with more specific stage information
        raise StandardError, "Failed at normalizing entry #{index + 1}/#{feed_entries.size} (ID: #{feed_entry.id}): #{e.message}"
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
  rescue ArgumentError => e
    # Re-raise ArgumentError as-is for invalid normalizer configurations
    raise
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

  # Executes the loading step: loads feed contents and registers timing/size stats
  # @param feed [Feed] the feed to load
  # @return [String] raw feed data
  def execute_loading_step(feed)
    load_start = Time.current
    raw_data = load_feed_contents(feed)
    register_stats(load_duration: Time.current - load_start, content_size: raw_data.bytesize)
    raw_data
  end

  # Executes the processing step: processes content and registers timing/count stats
  # @param feed [Feed] the feed being processed
  # @param raw_data [String] raw feed data
  # @return [Array<Hash>] processed feed entries
  def execute_processing_step(feed, raw_data)
    process_start = Time.current
    processed_entries = process_feed_contents(feed, raw_data)
    register_stats(process_duration: Time.current - process_start, total_entries: processed_entries.size)
    processed_entries
  end

  # Executes the persistence step: persists entries and registers count stats
  # @param feed [Feed] the feed to persist entries for
  # @param processed_entries [Array<Hash>] processed feed entries
  # @return [Array<FeedEntry>] newly created feed entries
  def execute_persistence_step(feed, processed_entries)
    new_feed_entries = persist_feed_entries(feed, processed_entries)
    register_stats(new_entries: new_feed_entries.size)
    new_feed_entries
  end

  # Executes the normalization step: normalizes entries and registers timing/result stats
  # @param new_feed_entries [Array<FeedEntry>] feed entries to normalize
  def execute_normalization_step(new_feed_entries)
    normalize_start = Time.current
    normalize_results = normalize_feed_entries(new_feed_entries)
    register_stats(
      normalize_duration: Time.current - normalize_start,
      new_posts: normalize_results[:valid_posts],
      invalid_posts: normalize_results[:invalid_posts]
    )
  end

  # Registers statistics values by merging them with existing stats
  # @param values [Hash] statistics values to register
  def register_stats(values = {})
    @stats = stats.merge(values)
  end

  # Returns current statistics hash, initializing if needed
  # @return [Hash] current statistics
  def stats
    @stats ||= FeedRefreshEvent.default_stats
  end

  # Finalizes statistics by calculating total duration and completion time
  # @return [Hash] finalized statistics
  def finalize_stats
    register_stats(
      total_duration: Time.current - @total_start,
      completed_at: Time.current.iso8601
    )
    stats
  end
end
