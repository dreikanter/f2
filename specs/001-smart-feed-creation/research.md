# Phase 0 Research: Smart Feed Creation

**Plan**: [`plan.md`](./plan.md)

The spec has zero remaining `NEEDS CLARIFICATION` markers (resolved during `/speckit-clarify`). This document resolves the *implementation forks* the parent design left open and the technology choices the new code introduces. Each section follows: **Decision** → **Rationale** → **Alternatives considered**.

---

## 1. Profile registry shape (parent spec phase 1, deferred decision)

**Decision**: Keep `FeedProfile` as a **Ruby module with a frozen `PROFILES` hash**, enriched with structured per-stage configuration. Profiles stay in code; the registry is loaded at boot.

```ruby
module FeedProfile
  PROFILES = {
    "rss" => {
      display_name: "RSS Feed",
      input_shape: :url,
      depends_on_ai: false,
      parameter_schema: { ... }, # JSON Schema
      loader:     { class: "Loader::HttpLoader",       config: {} },
      processor:  { class: "Processor::RssProcessor",  config: {} },
      normalizer: { class: "Normalizer::RssNormalizer", config: {} },
      title_extractor: "TitleExtractor::RssTitleExtractor",
      matcher: "ProfileMatcher::RssProfileMatcher"
    },
    # ...
  }.freeze
end
```

**Rationale**: The current registry is already a frozen hash; this evolves it without changing the storage shape. A DSL or YAML format would add infrastructure (parser, validator, hot-reload) for no near-term benefit. Profiles ship and version with the application — the same Git commit that adds a stage class adds the profile entry. The future move to a DB table is documented in the parent spec and kept out of v1.

**Alternatives considered**:
- *Small DSL (`profile :rss do ... end`)*: prettier authoring, but adds a parser to maintain. Reject for v1.
- *YAML files in `config/profiles/`*: separates data from code, but stage class names are still string-indirected and you lose Ruby's tooling (rubocop, autocomplete, refactoring). Reject for v1.
- *DB table with `system_owned: true` rows*: deferred to parent-spec future scope (user-authored profiles).

---

## 2. JSON Schema dialect (parent spec phase 1, deferred decision)

**Decision**: **Draft 2020-12** via the `json_schemer` gem.

**Rationale**: `json_schemer` is a maintained, fast Ruby validator with full Draft 2020-12 support, used by both the `parameter_schema` (feed-creation form generation + on-save validation) and the LLM `output_schema` (response validation). Draft 2020-12 is the current stable revision; OpenAI's `response_format: json_schema` documents Draft 2020-12 compatibility, so the same schema works across Anthropic (forced tool use, schema-as-tool-input) and OpenAI without translation.

**Alternatives considered**:
- *Draft 7 with `json-schema` gem*: oldest, widest, but Draft 7 lacks `prefixItems`, `unevaluatedProperties`, and other features useful for tightening AI output. Reject.
- *Mix dialects per use case*: complexity for no gain. Reject.

---

## 3. `Feed.url` migration (parent spec phase 1, deferred decision)

**Decision**: **Drop `feeds.url` as a top-level column; move source-side data into `feeds.params` (JSONB).** Per spec Assumption A6, no production data exists, so the migration is a straight drop-add (no backfill); reversibility is verified on an empty DB.

**Rationale**: Once `parameter_schema` drives form generation, every source-side value (URL, handle, query, refinement prompt) lives in `params`. Keeping `url` as a privileged top-level column would require the RSS profile to special-case it. Treating all source-side values uniformly under `params` eliminates the special case and aligns RSS, XKCD, AI-from-website, AI-handle-search, and AI-web-search under one shape.

`Feed#url` becomes a virtual attribute: `#url` reads `params["url"]` and `#url=` writes through to it (with whitespace stripped). This keeps existing controllers, views, fixtures, and strong-params plumbing unchanged.

**Alternatives considered**:
- *Keep `feeds.url` for backward-compat*: A6 frees us from this. Reject.
- *Move `url` to `params` but keep the column populated for legacy queries*: introduces a sync invariant. Reject.

---

## 4. Detection record schema (handoff D6)

**Decision**: Replace `feed_details.feed_profile_key` and `feed_details.title` with a single `candidates` JSONB column carrying the ranked list. The recommended candidate is just `candidates[0]`; there are no mirrored columns to keep in sync.

```sql
ALTER TABLE feed_details ADD COLUMN candidates JSONB NOT NULL DEFAULT '[]';
ALTER TABLE feed_details DROP COLUMN feed_profile_key;
ALTER TABLE feed_details DROP COLUMN title;
```

`candidates` shape (one entry per matching profile, ordered by rank):

```json
[
  { "profile_key": "rss", "title": "Example Blog",
    "depends_on_ai": false, "rank": 0, "rank_reason": "specific_match" },
  { "profile_key": "llm_website_extractor", "title": "Example Blog",
    "depends_on_ai": true, "rank": 1, "rank_reason": "ai_fallback" }
]
```

**Rationale**: One JSONB column avoids creating a `feed_detail_candidates` join table for what's a small, append-only, per-record list. No production data (A6), so dropping the redundant columns is a single migration with no backfill story. The previous design kept mirrored `feed_profile_key` / `title` columns "for backward compat", but the only reader of those columns was the controller's own `handle_success_status` — it now reads `candidates.first` directly.

**Alternatives considered**:
- *Separate `feed_detail_candidates` table*: relational normalization for no querying benefit. Reject.
- *Keep mirrored `feed_profile_key` / `title` columns*: requires a sync invariant nothing enforces; the JSONB is the source of truth. Reject.

---

## 5. LLM client: SDK choice and structured output

**Decision**: Implement `LlmClient` as a thin Ruby service over the **`ruby_llm` gem**, a maintained multi-provider abstraction (Anthropic, OpenAI, Gemini, Bedrock, OpenRouter, Ollama). The first provider shipped is Anthropic; OpenAI and others land later as registry entries with no new adapter code. Structured output is delegated to RubyLLM, which internally uses each provider's native mechanism (forced tool use for Anthropic, `response_format: json_schema` for OpenAI) so our code stays provider-agnostic.

`LlmClient` invokes RubyLLM directly — no separate adapter class. `LlmClient.for(feed)` resolves the user's credential, configures RubyLLM with the credential's API key and provider, and returns a client bound to that credential. `LlmClient.call` then handles schema validation, `LlmUsage` write, exception mapping, and the detection guard. Stage classes never see the provider name or RubyLLM.

**Rationale**: The spec's "two-axis" abstraction (credentials × providers) is exactly what RubyLLM is built for. Writing one adapter per provider would duplicate the work RubyLLM already does; switching SDKs lets us add providers as registry rows instead of code. RubyLLM exposes per-provider features critical to this spec: prompt-cache token counts (`cache_read_input_tokens` for Anthropic), provider-side server tools (Anthropic `web_search` / `web_fetch`), structured output via JSON Schema, and normalized usage telemetry. Our `LlmClient` shrinks to the parts that *should* be ours: credential resolution, `LlmUsage` persistence, schema validation via JSONSchemer, the detection-phase guard, and `Rails.error.report` routing.

**Test strategy**: Stage tests stub `LlmClient` with `Minitest::Mock` returning canned `(structured_output, usage)` tuples. `LlmClient` itself is tested end-to-end with `WebMock` against per-provider fixture responses (success, schema violation, provider error, rate limit, timeout). No VCR; cassettes drift and obscure intent.

**Alternatives considered**:
- *Direct `anthropic` Ruby gem*: works, but every new provider needs a hand-written adapter that re-derives auth/retry/tool/cache plumbing. Reject — RubyLLM removes that duplication.
- *Raw HTTP via existing `HttpClient`*: tracks every provider's API surface manually. Reject for v1.
- *VCR cassettes for adapter tests*: cassettes go stale, mask intent, and require periodic re-recording with real keys in CI. WebMock-with-fixtures is more maintainable.

**Caveats**:
- Solo-maintainer dependency. Pin a known-good version and review release notes before upgrading.
- Provider-specific quirks (new Anthropic server tools, vendor changes) may briefly lag the underlying API. If a profile needs a feature RubyLLM doesn't expose yet, an escape hatch is to bypass the wrapper for that one call — but we should treat that as exceptional, not a default.

---

## 6. Credential storage and encryption

**Decision**: `llm_credentials.credential_data` is a JSONB column encrypted at rest via Rails' built-in `encrypts :credential_data` (deterministic: `false`). Provider-specific schema (declared by the registry) defines what keys live inside (`api_key`, `organization_id`, `base_url`, etc.).

**Rationale**: Rails' built-in `ActiveRecord::Encryption` is configured project-wide and used elsewhere; reusing it keeps key rotation and audit consistent. JSONB lets each provider define its own shape without per-provider tables or sparse columns. Validating the shape on save uses the provider's declared schema (same `json_schemer` instance as elsewhere).

**Alternatives considered**:
- *Separate column per provider field*: sparse columns balloon as providers are added. Reject.
- *External secrets manager (Vault, etc.)*: overkill for v1; could be a future migration. Reject.
- *Plain text + filesystem permissions*: violates security baseline. Reject.

---

## 7. Default credential uniqueness

**Decision**: Enforce "at most one default per `(user_id, provider)`" via a **partial unique index** at the database level *plus* a model-level validation:

```sql
CREATE UNIQUE INDEX index_llm_credentials_one_default_per_provider
  ON llm_credentials (user_id, provider)
  WHERE is_default = TRUE;
```

Setting a credential as default un-defaults any other for the same user+provider in the same transaction (a `before_save` callback when `is_default` flips to `true`).

**Rationale**: Database constraint is the truth; model callback is the convenience. Belt and suspenders on a small invariant we can't relax without breaking the picker contract (FR-013).

**Alternatives considered**:
- *Application-level only*: race-condition risk between two simultaneous "Make default" clicks. Reject.
- *Boolean replaced by a `default_credential_id` on `users`*: harder to reason about with multiple providers; would need one column per provider or a join model. Reject.

---

## 8. Preview implementation strategy

**Decision**: **Reuse `FeedRefreshWorkflow` with a non-persistent mode.** Add a `preview: true` keyword to the workflow that:
- Limits the loader/processor to the first 5 items (loader contract gains an optional `limit:` param; AI loaders pass it through as part of the prompt; HTTP loaders take the first N entries).
- Skips persistence: `FeedEntry`/`Post` are constructed in memory and returned as a `Preview` value object (plain Ruby `Data` class).
- For AI stages, `LlmUsage` is still written, attributed to the `(user_id, profile_key, stage)` triple with `feed_id: nil` and `purpose: "preview"` (new column on `llm_usages`).

A thin `FeedPreviewService` orchestrates: takes a `(user, profile_key, params)` triple → temporarily constructs an unsaved `Feed` (in memory) → invokes `FeedRefreshWorkflow.new(feed, preview: true).call` → returns the resulting in-memory `Post` drafts.

**Rationale**: One pipeline for both real runs and previews avoids two sources of truth for "what does this feed publish?". The user is literally asking "what will this feed publish?" — the most accurate answer is "exactly what the same code path would produce." Marking AI-call provenance via `purpose: "preview"` keeps the cost-attribution surface honest (preview tokens are real costs).

**Alternatives considered**:
- *Separate `FeedPreviewWorkflow`*: drift risk between real and preview behavior. Reject.
- *Run real workflow with rollback*: pollutes the dedup table mid-transaction; awkward; surprising. Reject.
- *Render preview from cached `feed_entries` after the first scheduled run*: chicken-and-egg with the spec's "preview gates `enabled` state" rule. Reject.

---

## 9. AI-from-website `uid` strategy

**Decision**: For the `llm_website_extractor` profile, the LLM is **instructed to extract a stable per-item permalink URL from the page**, and the `uid` is the SHA-256 of the canonicalized permalink. If no permalink can be extracted (rare; pure-feed pages without per-item links), the `uid` is the SHA-256 of `(page_url, item_position, sanitized_title)` as a deterministic fallback.

The strategy is a profile-specific concern and lives in the profile's `output_schema` + prompt.

**Rationale**: Permalinks are the most stable per-item identity available; canonicalizing (lowercase host, drop `utm_*`, drop trailing slash) catches the common variations. The `(page_url, position, title)` fallback is deterministic enough for dedup-of-the-same-page-fetched-twice and cheap enough to compute in the normalizer.

**Alternatives considered**:
- *Hash the item body*: fails on minor edits. Reject.
- *Ask the LLM to invent a UID*: non-deterministic, bypasses the "no user-supplied schemas" principle. Reject.
- *Use page_url + published_at*: many pages don't have per-item published dates the LLM can reliably extract. Reject.

---

## 10. Input classifier placement

**Decision**: A standalone `InputClassifier` service (`app/services/input_classifier.rb`) returning a symbol: `:url | :handle | :query | :malformed`. Called once at the start of detection. Each `ProfileMatcher` declares the input shapes it accepts; the detector skips matchers whose shape doesn't accept the classified input.

**Rationale**: Single-responsibility separation. The detector orchestrates matchers; the classifier classifies inputs. Testing each in isolation is straightforward. Adding a new input shape (e.g., `:rss_opml`) is a one-line classifier change plus matchers that opt in.

Classification rules:
- `:url` — `URI.parse(input).is_a?(URI::HTTP)` succeeds and host is non-empty.
- `:handle` — matches `^@[A-Za-z0-9_]{1,30}(@[A-Za-z0-9.-]+)?$` (covers `@user` and `@user@instance.tld` for fediverse-shaped handles).
- `:query` — non-blank, ≥ 3 chars, ≤ 200 chars, doesn't match `:url` or `:handle`.
- `:malformed` — empty, whitespace-only, single character, or input that fits no shape.

**Alternatives considered**:
- *Method on `FeedProfileDetector`*: muddies single-responsibility. Reject.
- *Classification as part of each matcher (`accepts?(input)`)*: each matcher re-runs URL parsing etc. Wasteful. Reject.

---

## 11. Detection / preview state restoration on reload (FR-018, FR-019)

**Decision**: All state lives in `feed_details` and the (still in-progress) feed identifier travels in the URL. On reload:
- `feed_details` carries the ranked candidate list (no detection re-run).
- The user's selected candidate is stored client-side in the form's hidden field; on form re-render after reload, the hidden field is restored from the URL params (`?candidate=<profile_key>`).
- The cached preview lives in a per-user, per-feed-detail Rails cache entry keyed by `(feed_detail_id, profile_key, params_digest)`. The cache TTL matches the feed-detail row's lifetime (cleaned up by `cleanup_feed_identification` on save). On reload, the cached preview is re-rendered without spending tokens.
- "Refresh preview" busts the cache for that key and runs `FeedPreviewService` again.

**Rationale**: Reusing `feed_details` as the identifier (and the `cleanup_feed_identification` lifecycle) keeps the new flow inside the existing seams. Rails' built-in `Rails.cache` is enough for preview caching; no new persistent table needed. The cache key is a digest of inputs so that any source-side change naturally generates a new cache entry (FR-019: auto-re-run on source-side change).

**Alternatives considered**:
- *Persist previews in a new `feed_previews` table*: schema for cache. Reject — `Rails.cache` is the right primitive.
- *Session-bound state*: breaks across devices and sessions. Reject.

---

## 12. Multi-candidate UI as Turbo Frame vs Stream

**Decision**: Continue the existing Turbo-Stream pattern (`#feed-form` swap from the `_form_collapsed` → polling → `_form_expanded` shells). Add an inline candidate chooser inside `_form_expanded` (no separate route). A small Stimulus controller (`candidate_chooser_controller.js`) handles the local "switch selected option" interaction; switching a candidate emits a `feed:candidate-changed` event that `preview_controller.js` listens for and reloads the preview pane via a Turbo Frame request to the new `feed_preview` resource.

**Rationale**: Aligns with A4 ("disambiguation inline with confirmation step, not a separate page"). Existing polling/streaming machinery is reused; no new transport. Stimulus controllers stay scoped to single concerns.

**Alternatives considered**:
- *Separate `/feeds/new/candidates` route*: extra route, extra controller, extra back-button friction. Reject.
- *Single big Stimulus controller for chooser+preview+form*: violates the single-responsibility convention used elsewhere. Reject.

---

## Summary of resolved forks

| Fork | Source | Resolution |
|------|--------|-----------|
| Profile registry shape | Parent spec, phase 1 | Ruby module, enriched frozen `PROFILES` hash |
| JSON Schema dialect | Parent spec, phase 1 | Draft 2020-12 via `json_schemer` |
| `Feed.url` migration | Parent spec, phase 1 | Drop column; absorb into `feeds.params` |
| Detection record schema | Handoff D6 | `feed_details.candidates` JSONB; drop legacy `feed_profile_key` / `title` columns (no mirror) |
| LLM SDK + structured output | Plan-time | `ruby_llm` gem (multi-provider); `LlmClient` calls it directly with no intermediate adapter class |
| Credential storage | Parent spec, phase 2 | JSONB encrypted via Rails `encrypts`; provider-specific schema |
| Default-credential uniqueness | Spec FR-013 | Partial unique index + model callback |
| Preview implementation | Spec FR-014–019 | Reuse `FeedRefreshWorkflow` with `preview: true` mode |
| AI-from-website `uid` | Notes file open Q | LLM-extracted permalink, SHA-256 of canonicalized URL; deterministic fallback |
| Input classifier | Spec A5 | Standalone `InputClassifier` service |
| In-progress state restoration | Spec FR-018, FR-019 | `feed_details` row + Rails.cache for preview |
| Multi-candidate UI transport | Spec A4 | Turbo Stream swap of `#feed-form`; Stimulus for local interactions; Turbo Frame for preview reload |

All `NEEDS CLARIFICATION` markers from the spec: **none** (resolved during `/speckit-clarify`). All design forks above are the planning-time decisions that resolve the parent design's open questions.
