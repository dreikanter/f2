# Contract: Detection (input → ranked profile list)

**Audience**: code modifying `FeedProfileDetector`, `FeedDetailsFetcher`, or any future input matcher.
**Status**: planning-time (Phase 1 design output).

## Inputs

`FeedProfileDetector.call(input:, fetched_body: nil)` where:

- `input`: `String` — the user's raw input, trimmed.
- `fetched_body`: `String?` — the URL body if `InputClassifier` returned `:url` and `FeedDetailsFetcher` already fetched it; `nil` otherwise. Avoids double-fetching.

## Outputs

A `DetectionResult` value object (`Data.define`):

```ruby
DetectionResult.new(
  input_shape: :url,                       # one of :url, :handle, :query, :malformed
  candidates: [
    DetectionCandidate.new(
      profile_key: "rss",
      title: "Example Blog",                # filled by the profile's title_extractor when available
      depends_on_ai: false,
      rank: 0,
      rank_reason: :specific_match
    ),
    DetectionCandidate.new(
      profile_key: "llm_website_extractor",
      title: "Example Blog",
      depends_on_ai: true,
      rank: 1,
      rank_reason: :ai_fallback
    )
  ]
)
```

`candidates` is ordered by `rank` ascending (0 = recommended). Empty array means no profile matched and no AI fallback applies → `feed_details.status = :failed`. This is rare because at least one AI fallback usually applies for any non-malformed input.

## Ranking algorithm (deterministic, pure)

```text
For each matcher whose input_shape ∈ {input_shape, :any}:
  if matcher.match?(input, fetched_body):
    candidates << (profile_key, matcher.match_specificity, depends_on_ai)

Sort candidates by:
  primary:   depends_on_ai ASC                 # non-AI before AI
  secondary: match_specificity DESC            # specific before generic
  tertiary:  registration order ASC            # = index in FeedProfile::PROFILES insertion order

Assign rank = index after sort.
Record rank_reason as one of:
  :specific_match       (depends_on_ai = false, top-of-list)
  :generic_match        (depends_on_ai = false, not top)
  :ai_fallback          (depends_on_ai = true)
```

## Constraints

1. **Detection MUST be pure / read-only with respect to AI**: no `LlmClient` call may originate from a matcher's `match?`. Enforced by `LlmClient` itself, which raises if invoked from a thread tagged `:detection_thread`. Matchers may make a single HTTP fetch (already done by `FeedDetailsFetcher`).
2. **Idempotent**: calling `FeedProfileDetector.call` twice with the same `(input, fetched_body)` MUST produce identical results.
3. **Bounded**: total time inside `FeedProfileDetector.call` < 1 s (excluding the HTTP fetch which `FeedDetailsFetcher` performs separately under its 30 s budget).
4. **Errors**: any matcher that raises is reported via `Rails.error.report` with `matcher_class` and `input_shape` context, then skipped — one bad matcher MUST NOT block detection.

## Persistence

`FeedDetailsFetcher` writes the `DetectionResult` to `feed_details`:

- `feed_details.status = :success` if `candidates` non-empty, else `:failed`.
- `feed_details.candidates` = serialized array of candidate hashes (see [`../research.md`](../research.md) §4 for shape). Single source of truth — there are no mirrored `feed_profile_key` / `title` columns.

## Test contract

- `FeedProfileDetector` unit tests cover: zero matches, one non-AI match, one AI match, mixed (non-AI ranks above AI), specificity (XKCD outranks RSS for an `xkcd.com` URL), tiebreak by registration order, malformed-input early return, exception in one matcher doesn't abort the chain.
- `InputClassifier` tests cover each input shape and edge cases (whitespace, single character, fediverse handles, IDN URLs, query-shaped strings that look like URLs).
- `FeedDetailsFetcher` tests cover: persistence shape, error reporting, the no-double-fetch invariant.

## What changes for callers

- `FeedDetailsController#show` (the polling endpoint) must serialize `candidates` into the Turbo Stream payload; the `_form_expanded` partial reads it to render the chooser.
- The controller builds the in-progress `Feed` instance from `feed_detail.candidates.first` — `profile_key` and `title` come from the recommended candidate, not from columns on `feed_details`.
