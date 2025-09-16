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
    Rails.logger.info "Starting feed refresh for feed #{feed.id}"

    # Step 1: Load feed contents
    raw_data = load_feed_contents(feed)

    # Step 2: Process feed contents into structured entries
    processed_entries = process_feed_contents(feed, raw_data)

    # Step 3: Persist feed entries and get new ones
    new_feed_entries = persist_feed_entries(feed, processed_entries)

    # Step 4: Normalize each new feed entry into posts
    normalize_feed_entries(new_feed_entries)

    Rails.logger.info "Feed refresh completed for feed #{feed.id}, processed #{new_feed_entries.count} new entries"
  end

  # @param feed [Feed] the feed to load
  # @return [String] raw feed data
  def load_feed_contents(feed)
    loader_class = resolve_loader_class(feed.loader)
    loader = loader_class.new(feed)
    loader.load
  end

  # @param feed [Feed] the feed being processed
  # @param raw_data [String] raw feed data
  # @return [Array<Hash>] processed feed entries
  def process_feed_contents(feed, raw_data)
    processor_class = resolve_processor_class(feed.processor)
    processor = processor_class.new(feed, raw_data)
    processor.process
  end

  # @param feed [Feed] the feed to persist entries for
  # @param processed_entries [Array<Hash>] processed feed entries
  # @return [Array<FeedEntry>] newly created feed entries
  def persist_feed_entries(feed, processed_entries)
    new_entries = []

    processed_entries.each do |entry_data|
      uid = entry_data[:uid] || entry_data["uid"]
      next unless uid.present?

      # Check if entry already exists to avoid duplication
      existing_entry = feed.feed_entries.find_by(uid: uid)
      next if existing_entry

      # Create new feed entry
      feed_entry = feed.feed_entries.create!(
        uid: uid,
        published_at: entry_data[:published_at] || entry_data["published_at"],
        raw_data: entry_data[:raw_data] || entry_data["raw_data"] || entry_data,
        status: :pending
      )

      new_entries << feed_entry
    end

    new_entries
  end

  # @param feed_entries [Array<FeedEntry>] feed entries to normalize
  def normalize_feed_entries(feed_entries)
    return if feed_entries.empty?

    feed = feed_entries.first.feed
    normalizer_class = resolve_normalizer_class(feed.normalizer)

    feed_entries.each do |feed_entry|
      normalize_single_entry(feed_entry, normalizer_class)
    end
  end

  # @param feed_entry [FeedEntry] the feed entry to normalize
  # @param normalizer_class [Class] the normalizer class to use
  def normalize_single_entry(feed_entry, normalizer_class)
    normalizer = normalizer_class.new(feed_entry)
    post = normalizer.normalize

    # Update feed entry status based on post status
    case post.status
    when "rejected"
      feed_entry.update!(status: :rejected)
    when "enqueued"
      feed_entry.update!(status: :processed)
    else
      feed_entry.update!(status: :failed)
    end
  rescue StandardError => e
    Rails.logger.error "Failed to normalize feed entry #{feed_entry.id}: #{e.message}"
    feed_entry.update!(status: :failed)
  end

  # @param loader_name [String] name of the loader
  # @return [Class] loader class
  def resolve_loader_class(loader_name)
    "Loader::#{loader_name.camelize}".constantize
  rescue NameError
    raise ArgumentError, "Unknown loader: #{loader_name}"
  end

  # @param processor_name [String] name of the processor
  # @return [Class] processor class
  def resolve_processor_class(processor_name)
    "Processor::#{processor_name.camelize}".constantize
  rescue NameError
    raise ArgumentError, "Unknown processor: #{processor_name}"
  end

  # @param normalizer_name [String] name of the normalizer
  # @return [Class] normalizer class
  def resolve_normalizer_class(normalizer_name)
    "Normalizer::#{normalizer_name.camelize}".constantize
  rescue NameError
    raise ArgumentError, "Unknown normalizer: #{normalizer_name}"
  end
end
