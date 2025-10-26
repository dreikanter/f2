class FeedRefreshWorkflow
  include Workflow
  include StatsRecorder

  step :initialize_workflow
  step :load_feed_contents
  step :process_feed_contents
  step :filter_new_entries
  step :persist_entries
  step :normalize_entries
  step :persist_posts
  step :publish_posts
  step :finalize_workflow

  attr_reader :feed

  def initialize(feed)
    @feed = feed
  end

  private

  def after_step(_output)
    record_duration(current_step)
  end

  def on_error(error)
    record_error_stats(error, current_step: current_step)
    create_feed_refresh_error_event(error)
  end

  def initialize_workflow(*)
    record_started_at
  end

  def load_feed_contents(*)
    raw_data = feed.loader_instance.load
    record_stats(content_size: raw_data.bytesize)
    raw_data
  end

  def process_feed_contents(raw_data)
    processed_entries = feed.processor_instance(raw_data).process
    record_stats(total_entries: processed_entries.size)

    unidentified_count = processed_entries.count { |entry| entry.uid.blank? }
    record_stats(unidentified_entries: unidentified_count) if unidentified_count.positive?

    processed_entries.reject { |entry| entry.uid.blank? }
  end

  def filter_new_entries(processed_entries)
    return [] if processed_entries.empty?

    uids = processed_entries.map(&:uid)
    existing_uids = FeedEntryUid.where(feed_id: feed.id, uid: uids).pluck(:uid).to_set
    processed_entries.filter { |entry| existing_uids.exclude?(entry.uid) }
  end

  def persist_entries(new_entries)
    return [] if new_entries.empty?
    current_time = Time.current

    entries_data = new_entries.map { entry_data(_1, current_time) }
    entry_uids_data = new_entries.map { feed_entry_uid_data(_1, current_time) }

    ActiveRecord::Base.transaction do
      FeedEntry.insert_all(entries_data)
      FeedEntryUid.insert_all(entry_uids_data, unique_by: [:feed_id, :uid])
    end

    new_uids = new_entries.map(&:uid)
    persisted_entries = feed.feed_entries.where(uid: new_uids)

    record_stats(new_entries: persisted_entries.size)
    persisted_entries
  end

  def entry_data(feed_entry, current_time)
    {
      feed_id: feed.id,
      uid: feed_entry.uid,
      published_at: feed_entry.published_at,
      raw_data: feed_entry.raw_data,
      status: :pending,
      created_at: current_time,
      updated_at: current_time
    }
  end

  def feed_entry_uid_data(feed_entry, current_time)
    {
      feed_id: feed.id,
      uid: feed_entry.uid,
      imported_at: current_time,
      created_at: current_time,
      updated_at: current_time
    }
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
    return posts if posts.empty?
    current_time = Time.current

    posts_data = posts.map do |post|
      post.slice(:feed_id, :feed_entry_id, :uid, :content, :source_url, :published_at, :attachment_urls, :comments, :validation_errors, :status)
          .merge(created_at: current_time, updated_at: current_time)
    end

    Post.insert_all(posts_data) if posts_data.any?

    new_uids = posts.map(&:uid)
    persisted_posts = feed.posts.where(uid: new_uids).order(:published_at)

    record_stats(
      new_posts: persisted_posts.where(status: :enqueued).count,
      rejected_posts: persisted_posts.where(status: :rejected).count
    )

    persisted_posts
  end

  def publish_posts(persisted_posts)
    enqueued_posts = persisted_posts.select(&:enqueued?).sort_by(&:published_at)
    return persisted_posts if enqueued_posts.empty?

    published_count = 0
    failed_count = 0

    enqueued_posts.each do |post|
      begin
        publisher = FreefeedPublisher.new(post)
        freefeed_post_id = publisher.publish
        post.update!(status: :published, freefeed_post_id: freefeed_post_id)
        published_count += 1
      rescue => e
        post.update!(status: :failed)
        failed_count += 1
        Rails.logger.error "Failed to publish post #{post.id}: #{e.message}"
      end
    end

    record_stats(
      published_posts: published_count,
      failed_posts: failed_count
    )

    persisted_posts
  end

  def finalize_workflow(posts)
    published_posts_count = posts.count(&:published?)
    failed_posts_count = posts.count(&:failed?)
    rejected_posts_count = posts.count(&:rejected?)

    record_completed_at
    create_feed_refresh_stats_event

    # Record daily metrics (sparse data - only if there's activity)
    posts_count = posts.count { |p| p.enqueued? || p.published? }
    FeedMetric.record(
      feed: feed,
      date: Date.current,
      posts_count: posts_count,
      invalid_posts_count: rejected_posts_count
    )

    Rails.logger.info "Feed refresh completed for feed #{feed.id}: " \
                      "#{published_posts_count} published, " \
                      "#{failed_posts_count} failed, " \
                      "#{rejected_posts_count} rejected"

    posts
  end

  def record_duration(step_name)
    duration = step_durations[step_name].to_f
    stats_key = "#{step_name}_duration".to_sym
    record_stats(stats_key => duration)
  end

  def create_feed_refresh_stats_event
    Event.create!(
      type: "feed_refresh",
      level: :info,
      subject: feed,
      user: feed.user,
      message: "Feed refresh completed for #{feed.name}",
      metadata: { stats: stats }
    )
  end

  def create_feed_refresh_error_event(error)
    Event.create!(
      type: "feed_refresh_error",
      level: :error,
      subject: feed,
      user: feed.user,
      message: "Feed refresh failed at #{current_step}: #{error.message}",
      metadata: {
        stats: stats,
        error: {
          class: error.class.name,
          message: error.message,
          stage: current_step.to_s,
          backtrace: error.backtrace
        }
      }
    )
  end
end
