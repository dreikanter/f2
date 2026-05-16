# In-memory preview of a feed. Runs the loader/processor/normalizer
# pipeline against a non-persisted Feed instance, returns a Preview of
# 2–5 PostDrafts, and mints a preview_token gating Feed#enable.
#
# Per contracts/preview.md the long-term plan is to share one workflow
# with FeedRefreshWorkflow (preview: true mode). For now this service
# drives the pipeline directly to keep the preview path simple and
# orthogonal to the persistence-heavy refresh workflow.
class FeedPreviewService
  Preview = Data.define(
    :posts,
    :generated_at,
    :source_summary,
    :used_ai,
    :llm_usage_id,
    :preview_token
  )

  PostDraft = Data.define(
    :title,
    :body,
    :supplementary,
    :images,
    :source_url,
    :published_at,
    :uid
  )

  Error = Class.new(StandardError)
  SourceUnreachable = Class.new(Error)
  Empty = Class.new(Error)
  AiUnparseable = Class.new(Error)
  ProviderError = Class.new(Error)
  CredentialMissing = Class.new(Error)

  CACHE_TTL = 24.hours
  LIMIT_RANGE = (2..5).freeze

  class << self
    def call(**args)
      new(**args).call
    end
  end

  def initialize(
    user:,
    profile_key:,
    params:,
    llm_credential: nil,
    cache_key: nil,
    refresh: false,
    limit: 5
  )
    @user = user
    @profile_key = profile_key
    @params = params || {}
    @llm_credential = llm_credential
    @cache_key = cache_key
    @refresh = refresh
    @limit = limit.to_i.clamp(LIMIT_RANGE.min, LIMIT_RANGE.max)
  end

  def call
    raise CredentialMissing if profile_depends_on_ai? && llm_credential.nil?

    cached = read_cache
    return cached if cached

    preview = compute_preview
    write_cache(preview)
    preview
  end

  private

  attr_reader :user, :profile_key, :params, :llm_credential, :cache_key, :refresh, :limit

  def profile_depends_on_ai?
    FeedProfile.depends_on_ai?(profile_key)
  end

  def read_cache
    return nil if refresh || cache_key.blank?

    Rails.cache.read(cache_key)
  end

  def write_cache(preview)
    return if cache_key.blank?

    Rails.cache.write(cache_key, preview, expires_in: CACHE_TTL)
  end

  def compute_preview
    temp_feed = build_temp_feed
    raw_data = load_raw(temp_feed)
    entries = process_entries(temp_feed, raw_data)
    raise Empty if entries.empty?

    posts = normalize_to_drafts(temp_feed, entries)
    raise Empty if posts.empty?

    Preview.new(
      posts: posts,
      generated_at: Time.current,
      source_summary: build_source_summary,
      used_ai: profile_depends_on_ai?,
      llm_usage_id: nil,
      preview_token: mint_token
    )
  end

  def build_temp_feed
    Feed.new(user: user, feed_profile_key: profile_key, params: params)
  end

  def load_raw(temp_feed)
    temp_feed.loader_instance.load
  rescue StandardError => e
    Rails.error.report(e, context: { profile_key: profile_key, user_id: user&.id })
    raise SourceUnreachable, e.message
  end

  def process_entries(temp_feed, raw_data)
    entries = temp_feed.processor_instance(raw_data).process
    entries = entries.reject { |entry| entry.uid.blank? }
    entries.first(limit)
  rescue StandardError => e
    Rails.error.report(e, context: { profile_key: profile_key, user_id: user&.id })
    raise SourceUnreachable, e.message
  end

  def normalize_to_drafts(temp_feed, entries)
    entries.map do |entry|
      temp_entry = FeedEntry.new(
        uid: entry.uid,
        published_at: entry.published_at,
        raw_data: entry.raw_data,
        feed: temp_feed
      )
      post = temp_feed.normalizer_instance(temp_entry).normalize
      build_post_draft(post, entry)
    end
  end

  def build_post_draft(post, entry)
    PostDraft.new(
      title: post.try(:title).to_s,
      body: post.content.to_s,
      supplementary: Array(post.comments),
      images: Array(post.attachment_urls),
      source_url: post.source_url.to_s,
      published_at: post.published_at || entry.published_at,
      uid: entry.uid
    )
  end

  def build_source_summary
    label = FeedProfile.display_name_for(profile_key)
    source_hint = params["url"].presence || params.values.first.to_s
    source_hint.present? ? "#{label}: #{source_hint}" : label
  end

  def mint_token
    PreviewToken.sign(
      user_id: user&.id,
      profile_key: profile_key,
      params: params,
      generated_at: Time.current
    )
  end
end
