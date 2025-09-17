class FeedRefreshJob < ApplicationJob
  include WorkflowExecutor

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
    execute_workflow(feed: feed) do
      step :initialize_workflow
      step :load_feed_contents_step
      step :process_feed_contents_step
      step :persist_feed_entries_step
      step :normalize_feed_entries_step
      step :finalize_workflow
    end
  end

  # Step implementations - clean, focused methods
  def initialize_workflow(ctx)
    ctx.start_timer(:total)
    ctx.log_info "Starting feed refresh for feed #{ctx.feed.id}"
  end

  def load_feed_contents_step(ctx)
    ctx.start_timer(:load)
    ctx.raw_data = load_feed_contents(ctx.feed)
    ctx.record_stats(
      load_duration: ctx.end_timer(:load),
      content_size: ctx.raw_data.bytesize
    )
  end

  def process_feed_contents_step(ctx)
    ctx.start_timer(:process)
    ctx.processed_entries = process_feed_contents(ctx.feed, ctx.raw_data)
    ctx.record_stats(
      process_duration: ctx.end_timer(:process),
      total_entries: ctx.processed_entries.size
    )
  end

  def persist_feed_entries_step(ctx)
    ctx.new_feed_entries = persist_feed_entries(ctx.feed, ctx.processed_entries)
    ctx.record_stats(new_entries: ctx.new_feed_entries.size)
  end

  def normalize_feed_entries_step(ctx)
    return ctx.record_stats(new_posts: 0, invalid_posts: 0) if ctx.new_feed_entries.empty?

    ctx.start_timer(:normalize)
    normalize_results = normalize_feed_entries(ctx.new_feed_entries)
    ctx.record_stats(
      normalize_duration: ctx.end_timer(:normalize),
      new_posts: normalize_results[:valid_posts],
      invalid_posts: normalize_results[:invalid_posts]
    )
  end

  # Original methods for backward compatibility and testing
  def load_feed_contents(feed)
    feed.loader_instance.load
  rescue ArgumentError => e
    # Re-raise ArgumentError as-is for invalid loader configurations
    raise
  rescue StandardError => e
    raise StandardError, "Failed to load feed from URL #{feed.url}: #{e.message}"
  end

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
        Rails.logger.error "Failed to normalize entry #{index + 1}/#{feed_entries.size} (ID: #{feed_entry.id}): #{e.message}"
        invalid_posts += 1
        # Continue processing other entries - normalization errors are not critical
      end
    end

    { valid_posts: valid_posts, invalid_posts: invalid_posts }
  end

  def finalize_workflow(ctx)
    ctx.record_stats(
      total_duration: ctx.end_timer(:total),
      completed_at: Time.current.iso8601
    )

    FeedRefreshEvent.create_stats(ctx.feed, ctx.stats)
    ctx.log_info "Feed refresh completed for feed #{ctx.feed.id}, processed #{ctx.new_feed_entries.count} new entries"
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
end
