class FeedRefreshWorkflow
  include Workflow
  include StatsRecorder

  step :interrupt_abandoned_refresh_events
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
    record_error_stats(current_step: current_step)
    fail_refresh_event(error)
    feed.record_refresh_failure!
  end

  def initialize_workflow(*)
    record_started_at
    @refresh_event = create_refresh_event
  end

  # FeedRefreshJob's advisory lock allows one refresh per feed at a time, so
  # an event still "started" when a new run begins belongs to a run whose
  # process died before finalizing. Demoting to debug takes the dead run's
  # "in progress" record out of the user event feed.
  def interrupt_abandoned_refresh_events(input = nil)
    feed.events.where(type: "feed_refresh")
        .where("metadata ->> 'status' = 'started'")
        .find_each do |event|
      interrupt_abandoned_event(event)
      Metrics.increment("feed_refresh_total", status: "interrupted", profile: feed.feed_profile_key)
      Rails.logger.info "Feed refresh interrupted for feed #{feed.id}: event #{event.id} was abandoned by a dead run"
    end

    input
  end

  # Existing references retain partial spend from a process that died.
  def interrupt_abandoned_event(event)
    search_event_ids = event.event_references.where(reference_type: "Event").pluck(:reference_id)
    stats_updates = LlmUsageReport.for_event(event).totals.event_stats.stringify_keys
    metadata = event.metadata.merge("status" => "interrupted")

    stats_updates["search_calls"] = search_event_ids.size if search_event_ids.any?
    metadata["stats"] = metadata.fetch("stats", {}).merge(stats_updates) if stats_updates.any?

    event.update!(level: :debug, metadata: metadata)
  end

  # The in-flight record is user-visible and ephemeral: completion or failure
  # deletes it and creates the permanent outcome event in its place, so each
  # run leaves exactly one lasting record.
  def create_refresh_event
    Event.create!(
      type: "feed_refresh",
      level: :info,
      subject: feed,
      user: feed.user,
      metadata: { status: "started", stats: stats }
    )
  end

  def load_feed_contents(*)
    raw_data = feed.loader_instance(refresh_event: @refresh_event).load
    record_stats(content_size: content_bytesize(raw_data))
    raw_data
  end

  def process_feed_contents(raw_data)
    processed_entries = feed.processor_instance(raw_data).process.entries
    record_stats(total_entries: processed_entries.size)

    identified_entries, unidentified_entries = processed_entries.partition { |entry| entry.uid.present? }
    record_stats(unidentified_entries: unidentified_entries.size) if unidentified_entries.any?

    identified_entries
  end

  def filter_new_entries(processed_entries)
    return [] if processed_entries.empty?

    deduped_entries = collapse_duplicate_uids(processed_entries)
    uids = deduped_entries.map(&:uid)
    existing_uids = FeedEntryUid.where(feed_id: feed.id, uid: uids).pluck(:uid).to_set
    record_stats(already_published_entries: existing_uids.size) if feed.feed_profile_key == "llm" && existing_uids.any?
    if feed.feed_profile_key == "llm" && existing_uids.size == deduped_entries.size && stats[:unidentified_entries].to_i.zero?
      record_stats(ai_outcome: "already_published")
    end
    new_entries = deduped_entries.filter { |entry| existing_uids.exclude?(entry.uid) }
    reject_entries_before_threshold(new_entries)
  end

  # Two items in one batch can resolve to the same uid (e.g. a utm_ variant and
  # the clean permalink, both normalized by Uid::Resolver). Keep the first and
  # drop the rest, so insert_all doesn't hit the unique index and roll back the
  # whole batch.
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

    ApplicationRecord.transaction do
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
    current_time = Time.current

    posts_data = posts.map do |post|
      post.slice(:feed_id, :feed_entry_id, :uid, :content, :source_url, :published_at, :attachment_urls, :comments, :validation_errors, :status)
          .merge(created_at: current_time, updated_at: current_time)
    end

    Post.insert_all(posts_data) if posts_data.any?
    feed.refresh_post_stats!

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
    if feed.feed_profile_key == "llm"
      outcome = if stats[:total_entries].to_i.zero?
        "no_candidates_returned"
      elsif enqueued_posts_count.positive?
        "posts_queued"
      elsif rejected_posts_count.positive?
        "candidates_rejected"
      elsif stats[:ai_outcome] == "already_published"
        "already_published"
      else
        "no_publishable_candidates"
      end
      record_stats(ai_outcome: outcome)
    end
    feed.reset_refresh_failures!
    Metrics.increment("feed_refresh_total", status: "ok", profile: feed.feed_profile_key)
    complete_refresh_event(posts)

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

  # A fresh terminal id makes cursor-based event polling discover the outcome.
  def complete_refresh_event(posts)
    search_event_ids = run_web_search_event_ids
    record_llm_usage_stats
    record_web_search_stats(search_event_ids)

    event = replace_refresh_event(level: :info, metadata: { status: "completed", stats: stats })

    @refresh_completed = true
    reference_posts(event, posts)
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

  def record_llm_usage_stats
    return unless @refresh_event

    record_stats(LlmUsageReport.for_event(@refresh_event).totals.event_stats)
  end

  def run_web_search_event_ids
    @refresh_event.event_references.where(reference_type: "Event").pluck(:reference_id)
  end

  def record_web_search_stats(search_event_ids)
    record_stats(search_calls: search_event_ids.size) if search_event_ids.any?
  end

  def replace_refresh_event(**attributes)
    Event.transaction do
      feed.record_successful_refresh! if attributes.dig(:metadata, :status) == "completed"
      event = Event.create!(type: "feed_refresh", subject: feed, user: feed.user, **attributes)
      if @refresh_event
        @refresh_event.event_references.update_all(event_id: event.id, updated_at: Time.current)
        @refresh_event.destroy!
      end
      event
    end
  end

  # The @refresh_completed guard keeps the invariant of at most one terminal
  # event per run: a failure after completion (e.g. metrics recording) must
  # not add a contradictory failed record.
  def fail_refresh_event(error)
    return if @refresh_completed

    search_event_ids = @refresh_event ? run_web_search_event_ids : []
    record_llm_usage_stats
    record_web_search_stats(search_event_ids)

    replace_refresh_event(
      level: :error,
      message: error.message,
      metadata: {
        status: "failed",
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
