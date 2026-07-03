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
  step :enqueue_publication
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
    Metrics.increment("feed_refresh_total", status: "error", profile: feed.feed_profile_key)
    record_error_stats(error, current_step: current_step)
    disable_credential_on_auth_error(error)
    create_feed_refresh_error_event(error)
    feed.record_refresh_failure!
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
    processed_entries = feed.processor_instance(raw_data).process.entries
    record_stats(total_entries: processed_entries.size)

    unidentified_count = processed_entries.count { |entry| entry.uid.blank? }
    record_stats(unidentified_entries: unidentified_count) if unidentified_count.positive?

    processed_entries.reject { |entry| entry.uid.blank? }
  end

  def filter_new_entries(processed_entries)
    return [] if processed_entries.empty?

    deduped_entries = collapse_duplicate_uids(processed_entries)
    uids = deduped_entries.map(&:uid)
    existing_uids = FeedEntryUid.where(feed_id: feed.id, uid: uids).pluck(:uid).to_set
    new_entries = deduped_entries.filter { |entry| existing_uids.exclude?(entry.uid) }
    reject_entries_before_threshold(new_entries)
  end

  # Two items in one batch can resolve to the same uid (e.g. a utm_ variant and
  # the clean permalink, both normalized by Uid::Resolver). Keep the first and
  # drop the rest, so insert_all doesn't hit the unique index and roll back the
  # whole batch. Also enforces the digest regime's one-post-per-period invariant.
  def collapse_duplicate_uids(entries)
    unique_entries = entries.uniq(&:uid)

    collapsed_count = entries.size - unique_entries.size
    record_stats(collapsed_duplicate_uids: collapsed_count) if collapsed_count.positive?

    unique_entries
  end

  # Entries at or before the feed's import threshold are dropped without
  # recording their UIDs, so clearing the threshold later lets them import
  # on a subsequent refresh. Entries without a published date pass through:
  # we can't tell how old they are, and silently losing them is worse.
  def reject_entries_before_threshold(entries)
    threshold = feed.import_after
    return entries if threshold.blank?

    fresh_entries, stale_entries = entries.partition do |entry|
      entry.published_at.nil? || entry.published_at > threshold
    end

    record_stats(entries_before_threshold: stale_entries.size) if stale_entries.any?
    fresh_entries
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

  # Hands publishing off to the async FIFO chain (see PostPublishJob) instead of
  # publishing inline. Kicking it on every refresh also restarts a chain that
  # may have stalled, so it doubles as the chain's watchdog.
  def enqueue_publication(persisted_posts)
    PostPublishJob.perform_later(feed.id) if persisted_posts.any?(&:enqueued?)
    persisted_posts
  end

  def finalize_workflow(posts)
    enqueued_posts_count = posts.count(&:enqueued?)
    rejected_posts_count = posts.count(&:rejected?)

    record_completed_at
    feed.reset_refresh_failures!
    Metrics.increment("feed_refresh_total", status: "ok", profile: feed.feed_profile_key)
    create_feed_refresh_stats_event(posts)

    # Record daily metrics (sparse data - only if there's activity)
    posts_count = posts.count { |p| p.enqueued? || p.published? }
    FeedMetric.record(
      feed: feed,
      date: Date.current,
      posts_count: posts_count,
      invalid_posts_count: rejected_posts_count
    )

    Rails.logger.info "Feed refresh completed for feed #{feed.id}: " \
                      "#{enqueued_posts_count} queued for publishing, " \
                      "#{rejected_posts_count} rejected"

    posts
  end

  def record_duration(step_name)
    duration = step_durations[step_name].to_f
    stats_key = "#{step_name}_duration".to_sym
    record_stats(stats_key => duration)
  end

  def create_feed_refresh_stats_event(posts)
    event = Event.create!(
      type: "feed_refresh",
      level: :info,
      subject: feed,
      user: feed.user,
      message: "",
      metadata: { stats: stats }
    )

    reference_posts(event, posts)
    event
  end

  def reference_posts(event, posts)
    return if posts.empty?

    references_data = posts.map do |post|
      {
        event_id: event.id,
        reference_type: "Post",
        reference_id: post.id,
        created_at: event.created_at,
        updated_at: event.created_at
      }
    end

    EventReference.insert_all(references_data)
  end

  def disable_credential_on_auth_error(error)
    return unless error.is_a?(LlmClient::AuthError)
    return unless feed.ai_credential

    feed.ai_credential.disable_credential_and_feeds(last_error: error.message)
  end

  def create_feed_refresh_error_event(error)
    Event.create!(
      type: "feed_refresh_error",
      level: :error,
      subject: feed,
      user: feed.user,
      message: error.message,
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
