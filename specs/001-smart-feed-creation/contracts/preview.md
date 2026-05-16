# Contract: `FeedPreviewService`

**Audience**: feed-creation controllers, the preview Stimulus controller, the preview job.
**Status**: planning-time (Phase 1 design output).

`FeedPreviewService` produces an in-memory preview of a feed without persisting anything. It reuses `FeedRefreshWorkflow` with a `preview: true` mode (research §8) so previews and scheduled runs share one code path.

## Inputs

```ruby
FeedPreviewService.call(
  user:           User,
  profile_key:    String,
  params:         Hash,                    # what would become feed.params
  llm_credential: LlmCredential?,          # required if profile depends_on_ai
  cache_key:      String?,                 # if provided, cache hit returns immediately
  refresh:        Boolean,                 # default false; true bypasses cache
  limit:          Integer                  # default 5; clamped 2..5
)
```

## Outputs

```ruby
Preview.new(
  posts:          [PostDraft, ...],        # 0..limit in-memory drafts (not persisted)
  generated_at:   Time,
  source_summary: String,                  # human-readable "Source: Example Blog (RSS)"
  used_ai:        Boolean,                 # mirrors profile.depends_on_ai for UI
  llm_usage_id:   Integer?,                # set when used_ai = true
  preview_token:  String                   # one-shot token tying this successful preview to a subsequent feed save (see Feed#enabling_requires_recent_preview)
)
```

`PostDraft` is a `Data.define` carrying the universal post shape:

```ruby
PostDraft.new(
  title:         String,
  body:          String,
  supplementary: [String],                 # 0+ comments
  images:        [String],                 # URLs
  source_url:    String,
  published_at:  Time,
  uid:           String                    # the dedup identifier
)
```

`preview_token` is a HMAC of `(user_id, profile_key, params_digest, generated_at)` signed by `Rails.application.secret_key_base`. Validated by `FeedsController#create` and `FeedsController#update` when the request asks to save in `enabled` state. Tokens expire 60 minutes after `generated_at`.

## Failure mode

```ruby
FeedPreviewService.call(...)
# → may raise:
#   FeedPreviewService::SourceUnreachable        — loader couldn't fetch
#   FeedPreviewService::Empty                    — loader/processor returned 0 items
#   FeedPreviewService::AiUnparseable            — LlmClient::SchemaError
#   FeedPreviewService::ProviderError            — LlmClient::ProviderError or RateLimited
#   FeedPreviewService::CredentialMissing        — depends_on_ai but no llm_credential passed
```

The controller catches each, surfaces the appropriate user copy (FR-017), and offers retry / save-as-disabled / back-out (FR-018, edge cases). Each failure also reports through `Rails.error.report` with `user_id`, `profile_key`, `params_digest`.

## Caching

When `cache_key` is provided and `refresh: false`:

- Cache hit → return the cached `Preview` immediately. No LLM call. No `LlmUsage` row written.
- Cache miss → compute preview, write to cache, return.

Cache key construction (computed by caller, not service): `Digest::SHA256.hexdigest("preview:#{feed_detail_id}:#{profile_key}:#{params.to_json}")`. TTL: 24 hours (longer than any reasonable in-progress flow).

**Invalidation**:
1. `FeedDetailsController#destroy` (the user-initiated cancel from T032) deletes the entry as part of `cleanup_feed_identification`.
2. `FeedsController#create` deletes the entry in the same `cleanup_feed_identification` call after the feed is saved.
3. `FeedsController#update` deletes the entry when a source-side field changes (the same code path that re-runs detection per FR-026 / FR-027).
4. `refresh: true` is the "Refresh preview" button: bust the cache for the key, recompute, write fresh.
5. TTL expiry (24h) is the backstop for cases none of the above fire (user closed the tab).

A saved feed being edited never reuses an old preview cache entry — the feed-edit flow starts a fresh `FeedDetail` so the cache key (which embeds `feed_detail_id`) is necessarily different.

## Background execution

`FeedPreviewJob` wraps `FeedPreviewService.call` for the async path (preview is requested by the controller, runs in the job, results land in cache, polling shell picks them up via Turbo Stream). For non-AI profiles fast enough to run synchronously (< 2s), the controller may call `FeedPreviewService.call` inline and respond directly. The job exists for AI-backed previews and slow HTTP fetches.

## Test contract

- `FeedPreviewService` unit tests: success path, each failure mode, cache hit, cache miss, refresh-bypass, limit clamping, preview_token shape.
- `FeedPreviewJob` tests: success → cache populated → Turbo Stream broadcast; failure → cache populated with failure marker → Turbo Stream broadcast.
- `FeedRefreshWorkflow` tests gain a `preview: true` parameter assertion; the existing real-run tests cover `preview: false`.

## Constraints

1. **Never persists.** Not `FeedEntry`, not `Post`, not anything except `LlmUsage` (when AI was called).
2. **Same code path as scheduled runs.** Diverging here is forbidden; if a behavior must differ between preview and run (e.g., loader limit), it goes through the `preview: true` parameter, not a separate workflow.
3. **AI cost is honest.** Preview LLM calls write `LlmUsage` with `purpose: :preview`. They count against the user's spend.
4. **Detection-forbidden guard does not apply here.** `FeedPreviewService` is not detection — by the time it runs, the user has explicitly picked an AI candidate.
