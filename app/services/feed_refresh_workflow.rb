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

  def after_step(_output)
    record_duration(current_step)
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

    processed_entries.map(&:symbolize_keys).reject { |entry| entry[:uid].blank? }
  end

  def filter_new_entries(processed_entries)
    return [] if processed_entries.empty?

    uids = processed_entries.map { |entry| entry[:uid] }
    existing_uids = feed.feed_entries.where(uid: uids).pluck(:uid).to_set
    processed_entries.filter { |entry| existing_uids.exclude?(entry[:uid]) }
  end

  def persist_entries(new_entries)
    return [] if new_entries.empty?
    current_time = Time.current

    entries_data = new_entries.map do |entry_data|
      {
        feed_id: feed.id,
        uid: entry_data.fetch(:uid),
        published_at: entry_data[:published_at],
        raw_data: entry_data[:raw_data] || entry_data,
        status: :pending,
        created_at: current_time,
        updated_at: current_time
      }
    end

    FeedEntry.insert_all(entries_data)
    new_uids = new_entries.map { |e| e[:uid] }
    persisted_entries = feed.feed_entries.where(uid: new_uids)

    record_stats(new_entries: persisted_entries.size)
    persisted_entries
  end

  def normalize_entries(persisted_feed_entries)
    persisted_feed_entries.map do |feed_entry|
      normalizer = feed.normalizer_instance
      post = normalizer.normalize(feed_entry)
      feed_entry.update!(status: :processed)
      post
    end
  end

  def persist_posts(posts)
    draft_posts = posts.select(&:draft?)
    return posts if draft_posts.empty?
    current_time = Time.current

    posts_data = draft_posts.map do |post|
      {
        feed_id: post.feed_id,
        feed_entry_id: post.feed_entry_id,
        uid: post.uid,
        content: post.content,
        source_url: post.source_url,
        published_at: post.published_at,
        status: :published,
        created_at: current_time,
        updated_at: current_time
      }
    end

    Post.insert_all(posts_data) if posts_data.any?
    posts
  end

  def finalize_workflow(posts)
    draft_posts_count = posts.count(&:draft?)
    rejected_posts_count = posts.count(&:rejected?)

    record_stats(
      new_posts: draft_posts_count,
      rejected_posts: rejected_posts_count,
      completed_at: Time.current,
      total_duration: total_duration
    )

    FeedRefreshEvent.create_stats(feed: feed, stats: stats)
    Rails.logger.info "Feed refresh completed for feed #{feed.id}, processed #{posts.count} posts"

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
