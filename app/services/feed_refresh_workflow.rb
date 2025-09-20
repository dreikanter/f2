class FeedRefreshWorkflow
  include Workflow

  step :initialize_workflow
  step :load_feed_contents
  step :process_feed_contents
  step :persist_feed_entries_workflow_step
  step :normalize_feed_entries_workflow_step
  step :finalize_workflow

  attr_reader :feed, :stats

  def initialize(feed)
    @feed = feed
    @stats = FeedRefreshEvent.default_stats
  end

  def execute
    super(feed, before: :before_step, after: :after_step, on_error: :handle_workflow_error)
  end

  private

  def before_step(step_name, input)
    Rails.logger.info "Starting step: #{step_name}"
  end

  def after_step(step_name, output)
    Rails.logger.info "Completed step: #{step_name}"
    record_step_duration_stats(step_name)
  end

  def handle_workflow_error(error)
    # Finalize partial stats from workflow duration
    stats[:total_duration] = total_duration
    stats[:failed_at_step] = current_step

    # Create error event
    FeedRefreshEvent.create_error(
      feed,
      error,
      current_step.to_s,
      stats
    )
  end

  # Step implementations - clean, focused methods
  def initialize_workflow(feed)
    Rails.logger.info "Starting feed refresh for feed #{feed.id}"
    { feed: feed }
  end

  def load_feed_contents(input)
    current_feed = input[:feed]
    raw_data = load_feed_content(current_feed)
    record_stats(content_size: raw_data.bytesize)
    input.merge(raw_data: raw_data)
  end

  def process_feed_contents(input)
    current_feed = input[:feed]
    processed_entries = process_feed_content(current_feed, input[:raw_data])
    record_stats(total_entries: processed_entries.size)
    input.merge(processed_entries: processed_entries)
  end

  def persist_feed_entries_workflow_step(input)
    current_feed = input[:feed]
    new_feed_entries = persist_feed_entries(current_feed, input[:processed_entries])
    record_stats(new_entries: new_feed_entries.size)
    input.merge(new_feed_entries: new_feed_entries)
  end

  def normalize_feed_entries_workflow_step(input)
    if input[:new_feed_entries].empty?
      record_stats(new_posts: 0, invalid_posts: 0)
      return input
    end

    normalize_results = normalize_feed_entries(input[:new_feed_entries])
    record_stats(
      new_posts: normalize_results[:valid_posts],
      invalid_posts: normalize_results[:invalid_posts]
    )
    input.merge(normalize_results: normalize_results)
  end

  def finalize_workflow(input)
    record_stats(
      completed_at: Time.current.rfc3339,
      total_duration: total_duration
    )

    current_feed = input[:feed]
    FeedRefreshEvent.create_stats(current_feed, stats)
    Rails.logger.info "Feed refresh completed for feed #{current_feed.id}, processed #{input[:new_feed_entries].count} new entries"
    input
  end

  def record_step_duration_stats(step_name)
    duration = step_durations[step_name]
    return unless duration

    stats_key = step_stats_key(step_name)
    record_stats(stats_key => duration) if stats_key
  end

  def step_stats_key(step_name)
    "#{step_name}_duration".to_sym
  end

  def record_stats(new_stats = {})
    stats.merge!(new_stats)
  end

  def load_feed_content(feed)
    feed.loader_instance.load
  rescue ArgumentError
    raise
  rescue StandardError => e
    raise StandardError, "Failed to load feed from URL #{feed.url}: #{e.message}"
  end

  def process_feed_content(feed, raw_data)
    entries = feed.processor_instance(raw_data).process
    normalize_entry_keys(entries)
  rescue ArgumentError
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
end
