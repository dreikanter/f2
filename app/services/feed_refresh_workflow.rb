class FeedRefreshWorkflow
  include Workflow

  attr_reader :feed, :stats, :timers

  def initialize(feed)
    @feed = feed
    @stats = FeedRefreshEvent.default_stats
    @timers = {}
  end

  def execute
    execute_workflow(feed, before: :before_step, after: :after_step) do |workflow|
      workflow.step :initialize_workflow
      workflow.step :load_feed_contents
      workflow.step :process_feed_contents
      workflow.step :persist_feed_entries_workflow_step
      workflow.step :normalize_feed_entries_workflow_step
      workflow.step :finalize_workflow
    end
  rescue StandardError => e
    handle_workflow_error(e)
    raise
  end

  private

  def before_step(step_name, input)
    Rails.logger.info "Starting step: #{step_name}"
    start_step_timer(step_name)
  end

  def after_step(step_name, output)
    Rails.logger.info "Completed step: #{step_name}"
    end_step_timer_and_record_stats(step_name, output)
  end

  def handle_workflow_error(error)
    # Finalize partial stats
    stats[:total_duration] = end_timer(:total, allow_missing: true) if timers[:total]
    stats[:failed_at_step] = @current_step

    # Create error event
    FeedRefreshEvent.create_error(
      feed,
      error,
      @current_step.to_s,
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
    raw_data = load_feed_contents_impl(current_feed)
    record_stats(content_size: raw_data.bytesize)
    input.merge(raw_data: raw_data)
  end

  def process_feed_contents(input)
    current_feed = input[:feed]
    processed_entries = process_feed_contents_impl(current_feed, input[:raw_data])
    record_stats(total_entries: processed_entries.size)
    input.merge(processed_entries: processed_entries)
  end

  def persist_feed_entries_workflow_step(input)
    current_feed = input[:feed]
    new_feed_entries = persist_feed_entries_impl(current_feed, input[:processed_entries])
    record_stats(new_entries: new_feed_entries.size)
    input.merge(new_feed_entries: new_feed_entries)
  end

  def normalize_feed_entries_workflow_step(input)
    if input[:new_feed_entries].empty?
      record_stats(new_posts: 0, invalid_posts: 0)
      return input
    end

    normalize_results = normalize_feed_entries_impl(input[:new_feed_entries])
    record_stats(
      new_posts: normalize_results[:valid_posts],
      invalid_posts: normalize_results[:invalid_posts]
    )
    input.merge(normalize_results: normalize_results)
  end

  def finalize_workflow(input)
    record_stats(completed_at: Time.current.iso8601)

    current_feed = input[:feed]
    FeedRefreshEvent.create_stats(current_feed, stats)
    Rails.logger.info "Feed refresh completed for feed #{current_feed.id}, processed #{input[:new_feed_entries].count} new entries"
    input
  end

  # Timer management
  def start_timer(name)
    timers[name] = Time.current
  end

  def end_timer(name, allow_missing: false)
    start_time = timers.delete(name)
    return 0.0 if start_time.nil? && allow_missing

    raise "Timer #{name} not found" if start_time.nil?

    Time.current - start_time
  end

  # Step timer management
  def start_step_timer(step_name)
    timer_name = step_timer_name(step_name)
    start_timer(timer_name) if timer_name
  end

  def end_step_timer_and_record_stats(step_name, output)
    timer_name = step_timer_name(step_name)
    return unless timer_name

    duration = end_timer(timer_name)
    stats_key = step_stats_key(step_name)
    record_stats(stats_key => duration) if stats_key
  end

  def step_timer_name(step_name)
    case step_name
    when :initialize_workflow then :total
    when :load_feed_contents then :load
    when :process_feed_contents then :process
    when :normalize_feed_entries_workflow_step then :normalize
    when :finalize_workflow then :total
    else nil
    end
  end

  def step_stats_key(step_name)
    case step_name
    when :load_feed_contents then :load_duration
    when :process_feed_contents then :process_duration
    when :normalize_feed_entries_workflow_step then :normalize_duration
    when :finalize_workflow then :total_duration
    else nil
    end
  end

  # Stats management
  def record_stats(new_stats = {})
    stats.merge!(new_stats)
  end

  # Original methods for backward compatibility and testing
  def load_feed_contents_impl(feed)
    feed.loader_instance.load
  rescue ArgumentError => e
    # Re-raise ArgumentError as-is for invalid loader configurations
    raise
  rescue StandardError => e
    raise StandardError, "Failed to load feed from URL #{feed.url}: #{e.message}"
  end

  def process_feed_contents_impl(feed, raw_data)
    entries = feed.processor_instance(raw_data).process
    normalize_entry_keys(entries)
  rescue ArgumentError => e
    # Re-raise ArgumentError as-is for invalid processor configurations
    raise
  rescue StandardError => e
    content_preview = raw_data.truncate(100) if raw_data.respond_to?(:truncate)
    raise StandardError, "Failed to process feed content (#{raw_data.bytesize} bytes, preview: '#{content_preview}'): #{e.message}"
  end

  def persist_feed_entries_impl(feed, processed_entries)
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

  def normalize_feed_entries_impl(feed_entries)
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
