class FeedRefreshWorkflow
  include Workflow

  step :initialize_workflow
  step :load_feed_contents
  step :process_feed_contents
  step :filter_new_entries
  step :persist_entries
  step :normalize_entries
  step :persist_posts
  step :finalize_workflow

  attr_reader :feed, :stats

  def initialize(feed)
    @feed = feed
    @stats = {}
  end

  private

  def before_step(step_name, input)
    Rails.logger.info "Starting step: #{step_name}"
  end

  def after_step(step_name, output)
    Rails.logger.info "Completed step: #{step_name}"
    record_duration(step_name)
  end

  def on_error(error)
    record_stats(
      total_duration: total_duration,
      failed_at_step: current_step
    )

    FeedRefreshEvent.create_error(
      feed: feed,
      error: error,
      stage: current_step.to_s,
      stats: stats
    )
  end

  def initialize_workflow(*)
    record_stats(started_at: Time.current)
  end

  def load_feed_contents(*)
    raw_data = feed.loader_instance.load(feed)
    record_stats(content_size: raw_data.bytesize)
    raw_data
  end

  def process_feed_contents(raw_data)
    processed_entries = feed.processor_instance(raw_data).process
    record_stats(total_entries: processed_entries.size)

    unidentified_count = processed_entries.count { |entry| entry[:uid].blank? }
    record_stats(unidentified_entries: unidentified_count) if unidentified_count.positive?

    processed_entries.map(&:symbolize_keys)
  end

  # TBD: Find new entries with one DB query
  def filter_new_entries(processed_entries)
    processed_entries.filter do |entry_data|
      uid = entry_data[:uid]
      uid.present? && !feed.feed_entries.exists?(uid: uid)
    end
  end

  # TBD: Persist all records with abatch insert
  def persist_entries(new_entries)
    persisted_entries = new_entries.map do |entry_data|
      uid = entry_data.fetch(:uid)

      feed.feed_entries.create!(
        uid: uid,
        published_at: entry_data[:published_at],
        raw_data: entry_data[:raw_data] || entry_data,
        status: :pending
      )
    end

    record_stats(new_entries: persisted_entries.size)
    persisted_entries
  end

  def normalize_entries(persisted_feed_entries)
    persisted_feed_entries.map do |feed_entry|
      normalizer = feed.normalizer_instance(feed_entry)
      post = normalizer.normalize
      feed_entry.update!(status: :processed)
      post
    end
  end

  def persist_posts(posts)
    # TBD: Persist new posts with a batch inset
    posts
  end

  def finalize_workflow(posts)
    invalid_posts_count = posts.count(&:rejected?)

    record_stats(
      new_posts: posts - invalid_posts_count,
      invalid_posts: invalid_posts_count,
      completed_at: Time.current,
      total_duration: total_duration
    )

    FeedRefreshEvent.create_stats(feed: feed, stats: stats)
    Rails.logger.info "Feed refresh completed for feed #{feed.id}, processed #{input[:new_feed_entries].count} new entries"

    posts
  end

  def record_duration(step_name)
    duration = step_durations[step_name].to_f
    stats_key = step_stats_key(step_name)
    record_stats(stats_key => duration)
  end

  def step_stats_key(step_name)
    "#{step_name}_duration".to_sym
  end

  def record_stats(new_stats = {})
    stats.merge!(new_stats)
  end
end
