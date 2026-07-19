class FeedPreviewWorkflow
  include Workflow
  include StatsRecorder

  step :initialize_workflow
  step :load_feed_contents
  step :process_feed_contents
  step :normalize_entries
  step :finalize_workflow

  attr_reader :feed_preview

  def initialize(feed_preview, run_id: nil, search_credential: nil)
    @feed_preview = feed_preview
    @run_id = run_id || feed_preview.run_id
    @search_credential = search_credential
  end

  private

  attr_reader :run_id, :search_credential

  # Conditional update: only the current run may transition the row. A stale
  # run (superseded by a newer enqueue that rewrote run_id) updates 0 rows.
  def transition!(attrs)
    scope = FeedPreview.where(id: feed_preview.id, run_id: run_id)
    updated = scope.update_all(attrs.merge(updated_at: Time.current))
    feed_preview.reload if updated.positive?
    updated.positive?
  end

  def on_error(error)
    record_error_stats(error, current_step: current_step)

    logger.error "FeedPreviewWorkflow error at #{current_step}: #{error.message}"

    transition!(status: FeedPreview.statuses[:failed])
  end

  def initialize_workflow(_input)
    record_started_at
    halt! unless transition!(status: FeedPreview.statuses[:processing])

    Feed.new(
      params: feed_preview.params,
      feed_profile_key: feed_preview.feed_profile_key,
      user: feed_preview.user,
      ai_credential_id: feed_preview.ai_credential_id,
      ai_model: feed_preview.ai_model,
      search_credential: search_credential
    )
  end

  def load_feed_contents(temp_feed)
    # `purpose` reaches LlmUsage via the loader's call context, so AI spend
    # from previews is distinguishable from scheduled runs.
    loader = temp_feed.loader_instance(purpose: :preview)
    raw_data = loader.load

    record_stats(content_size: content_bytesize(raw_data))
    { temp_feed: temp_feed, raw_data: raw_data }
  end

  # RSS/Atom loaders return a String body; AI loaders return an Array of items.
  def content_bytesize(raw_data)
    raw_data.respond_to?(:bytesize) ? raw_data.bytesize : raw_data.to_json.bytesize
  end

  def process_feed_contents(input)
    temp_feed = input[:temp_feed]
    raw_data = input[:raw_data]

    processor = temp_feed.processor_instance(raw_data)
    entries = processor.process.entries

    limited_entries = entries.first(FeedPreview::PREVIEW_POSTS_LIMIT)

    record_stats(total_entries: entries.size, preview_entries: limited_entries.size)
    { temp_feed: temp_feed, entries: limited_entries }
  end

  def normalize_entries(input)
    temp_feed = input[:temp_feed]
    entries = input[:entries]

    posts = entries.map do |entry|
      temp_feed_entry = FeedEntry.new(
        uid: entry.uid,
        published_at: entry.published_at,
        raw_data: entry.raw_data,
        feed: temp_feed
      )

      normalizer = temp_feed.normalizer_instance(temp_feed_entry)
      post = normalizer.normalize

      {
        content: post.content,
        source_url: post.source_url,
        published_at: post.published_at&.iso8601,
        attachments: post.attachment_urls || [],
        uid: entry.uid
      }
    end

    record_stats(normalized_posts: posts.size)
    posts
  end

  def finalize_workflow(posts)
    record_completed_at
    transition!(
      status: FeedPreview.statuses[:ready],
      ready_at: Time.current,
      data: { posts: posts, stats: stats }
    )
    posts
  end
end
