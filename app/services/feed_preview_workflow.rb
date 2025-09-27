class FeedPreviewWorkflow
  include Workflow
  include StatsRecorder

  step :initialize_workflow
  step :load_feed_contents
  step :process_feed_contents
  step :normalize_entries
  step :finalize_workflow

  attr_reader :feed_preview

  def initialize(feed_preview)
    @feed_preview = feed_preview
  end

  private

  def on_error(error)
    record_error_stats(error, current_step: current_step)

    logger.error "FeedPreviewWorkflow error at #{current_step}: #{error.message}"

    feed_preview.update!(status: :failed)
  end

  def initialize_workflow(_input)
    record_timing_stats(started_at: Time.current)
    feed_preview.update!(status: :processing)

    # Create a temporary feed object for workflow processing
    Feed.new(
      url: feed_preview.url,
      feed_profile: feed_preview.feed_profile,
      user: feed_preview.user
    )
  end

  def load_feed_contents(temp_feed)
    loader = temp_feed.loader_instance
    raw_data = loader.load

    record_stats(content_size: raw_data.size)
    { temp_feed: temp_feed, raw_data: raw_data }
  end

  def process_feed_contents(input)
    temp_feed = input[:temp_feed]
    raw_data = input[:raw_data]

    processor = temp_feed.processor_instance(raw_data)
    entries = processor.process

    # Limit to most recent entries for preview
    limited_entries = entries.first(FeedPreview::PREVIEW_POSTS_LIMIT)

    record_stats(total_entries: entries.size, preview_entries: limited_entries.size)
    { temp_feed: temp_feed, entries: limited_entries }
  end

  def normalize_entries(input)
    temp_feed = input[:temp_feed]
    entries = input[:entries]

    posts = entries.map do |entry|
      # Create a temporary feed entry for normalization
      temp_feed_entry = FeedEntry.new(
        uid: entry.uid,
        published_at: entry.published_at,
        raw_data: entry.raw_data,
        feed: temp_feed
      )

      normalizer = temp_feed.normalizer_instance(temp_feed_entry)
      post = normalizer.normalize

      # Convert post to JSON representation for storage
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
    record_timing_stats(completed_at: Time.current)

    feed_preview.update!(
      status: :ready,
      data: { posts: posts, stats: stats }
    )

    posts
  end
end
