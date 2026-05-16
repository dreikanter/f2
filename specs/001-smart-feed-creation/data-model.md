# Phase 1 Data Model: Smart Feed Creation

**Plan**: [`plan.md`](./plan.md) · **Research**: [`research.md`](./research.md)

## Overview

Three model changes (`Feed`, `FeedDetail`, `FeedProfile` registry) and two new models (`LlmCredential`, `LlmUsage`). One existing concept (`FeedEntry`, `Post`) gains structural fields to support the universal post shape from `notes/profile-contracts.md`.

```text
                  ┌──────────────┐
                  │     User     │
                  └──┬────┬───┬──┘
                     │    │   │
                     │    │   └──── has_many :llm_credentials
                     │    │
                     │    └──── has_many :feed_details
                     │
                     └──── has_many :feeds
                                   │
                                   ├── belongs_to :access_token        (existing)
                                   ├── belongs_to :llm_credential?     (new, optional)
                                   ├── has_many :feed_entries
                                   └── has_many :posts

LlmCredential ──── has_many :llm_usages
                              ▲
Feed ─── has_many :llm_usages │ (nullable feed_id for previews)
```

---

## 1. `LlmCredential` (new)

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | bigint | no | PK |
| `user_id` | bigint | no | FK → users; indexed |
| `provider` | string | no | e.g. `"anthropic"`, `"openai"`, `"openai_compatible"`. Validated against the credential-provider registry (see §6) |
| `display_name` | string | no | User-supplied label, max 80 chars, unique per `(user_id, provider)` |
| `credential_data` | jsonb | no | Provider-specific fields (API key, org id, base URL, …). Encrypted via Rails `encrypts` (deterministic: false) |
| `is_default` | boolean | no | Default `false`. Unique partial index: `(user_id, provider) WHERE is_default = TRUE` |
| `state` | integer (enum) | no | `pending: 0, validating: 1, active: 2, inactive: 3` (mirrors `AccessToken.status`) |
| `last_validated_at` | timestamp | yes | Set on each successful validation |
| `last_error` | text | yes | Provider-side validation error, if any |
| `created_at` / `updated_at` | timestamp | no | |

**Associations**:
- `belongs_to :user`
- `has_many :llm_usages`
- `has_many :feeds, foreign_key: :llm_credential_id` (a credential is referenced by feeds)

**Validations**:
- `provider`: presence, inclusion in registered providers
- `display_name`: presence, length ≤ 80, uniqueness scoped to `(user_id, provider)`
- `credential_data`: presence; shape validated against the provider's declared schema (`json_schemer`) on save
- `is_default`: at most one `true` per `(user_id, provider)` (model-level + DB partial unique index per research §7)

**State transitions**: `pending → validating → active | inactive`. Transitions identical to `AccessToken`. Validation runs in `LlmCredentialValidationJob` (small known-good provider call); a failed validation moves to `inactive` and records `last_error`.

**Lifecycle**:
- Created → enqueues validation job → moves to `validating` → settles to `active` or `inactive`.
- Marking another credential default un-defaults the previous one in the same transaction (`before_save` callback).
- Destroying a credential: nullifies `feeds.llm_credential_id`; for any feed left in `enabled` state without a usable credential, the feed is moved to `disabled` with an audit Event (existing pattern from `AccessToken#disable_associated_feeds`).
- `active → inactive` transition (provider revoked the key, or scheduled re-validation failed): same cascade as destroy — for any `enabled` feed using this credential and lacking another acceptable credential, move the feed to `disabled` with an audit Event. The credential row stays; only its reachability into `enabled` feeds is severed. User can fix the credential and re-enable the feed.

**Indexes**:
- `(user_id, provider, display_name)` unique
- `(user_id, provider) WHERE is_default = TRUE` unique partial
- `(user_id, state)` for filtering active credentials

---

## 2. `LlmUsage` (new)

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | bigint | no | PK |
| `user_id` | bigint | no | FK; indexed |
| `feed_id` | bigint | yes | FK; nullable for previews (purpose = `"preview"`) and ad-hoc credential-validation calls |
| `llm_credential_id` | bigint | yes | FK; nullable if the credential was destroyed before usage row was archived |
| `profile_key` | string | yes | Reference to the `FeedProfile` registry entry (string indirection because the registry is code-only in v1) |
| `stage` | integer (enum) | no | `loader: 0, processor: 1, normalizer: 2, validation: 3` (the last is for credential-validation calls) |
| `provider` | string | no | Snapshot of the provider used (e.g. `"anthropic"`) |
| `model` | string | no | Snapshot of the model (e.g. `"claude-opus-4-7"`) |
| `purpose` | integer (enum) | no | `scheduled_run: 0, preview: 1, validation: 2`. Scheduled-run is the default; preview / validation distinguish non-paying-feed costs |
| `input_tokens` | integer | no | From provider response |
| `output_tokens` | integer | no | From provider response |
| `cache_read_tokens` | integer | no | Default 0; Anthropic prompt-caching savings |
| `cost_estimate_cents` | integer | no | Computed at write time from a per-model rate table; stored so historical costs survive rate changes |
| `outcome` | integer (enum) | no | `success: 0, schema_error: 1, provider_error: 2, rate_limited: 3, timeout: 4` |
| `started_at` / `finished_at` | timestamp | no | For latency rollups |
| `created_at` / `updated_at` | timestamp | no | |

**Associations**:
- `belongs_to :user`
- `belongs_to :feed, optional: true`
- `belongs_to :llm_credential, optional: true`

**Validations**: presences as marked. No business validations beyond enums; this is an append-only audit trail.

**Indexes**:
- `(user_id, started_at)` for per-user usage rollups
- `(feed_id, started_at)` for per-feed cost panels
- `(profile_key, started_at)` for per-profile reliability rollups (operator concern)
- `(purpose, started_at)` for "preview vs scheduled-run" cost separation

**Notes on attribution (per research §8)**: previews always write a row with `feed_id: nil` and `purpose: :preview`. The user-visible AI usage page can choose to display preview spend separately from scheduled-run spend. SC-004 ("zero AI calls in detection") is auditable by `LlmUsage.where(stage: :detection)` returning empty — but `:detection` is intentionally **not** an enum value. Detection's no-AI rule is enforced by the absence of a code path that writes such a row.

---

## 3. `Feed` (modified)

| Column | Status | Notes |
|--------|--------|-------|
| `url` | **removed** | Replaced by `params["url"]` for profiles that accept URLs (research §3) |
| `params` | **added** | `jsonb`, default `{}`, validated against `FeedProfile[feed_profile_key].parameter_schema` on save |
| `llm_credential_id` | **added** | `bigint`, nullable, FK → llm_credentials. Required for AI-backed profiles (validated by `before_save` lookup against `FeedProfile`) |
| `state` | unchanged | `disabled: 0, enabled: 1`. Behavior changes per FR-016: `enabled` is settable only via flow that has just rendered a successful preview |
| All other columns | unchanged | |

**New / refined validations**:
- `params`: presence on save; schema-validated via `json_schemer` against `FeedProfile[feed_profile_key].parameter_schema`. Error messages map to per-field form errors.
- `llm_credential`: presence required when the profile `depends_on_ai`; otherwise must be `nil`. Validation reports the user-facing error as "Please add or pick AI credentials" (not "credential id missing").
- Custom guard `enabling_requires_recent_preview`: when `state` transitions `disabled → enabled`, the controller MUST attach a `preview_token` parameter (a one-shot token issued by `FeedPreviewService` after a successful preview, valid for the same in-progress flow). This keeps the "preview gates `enabled`" rule out of the model's hands while preventing controllers from saving `enabled` without preview proof.

**Convenience methods**:
- `Feed#url`: returns `params["url"]` (or `nil`).
- `Feed#requires_ai_credentials?`: derived from `FeedProfile[feed_profile_key].depends_on_ai`.
- `Feed#preview_cache_key`: digest of `(feed_profile_key, params)` for the Rails.cache lookup (research §11).

---

## 4. `FeedDetail` (modified)

| Column | Status | Notes |
|--------|--------|-------|
| `feed_profile_key` | unchanged | Now mirrors the **recommended** candidate (index 0 of `candidates`). Existing readers continue to work. |
| `title` | unchanged | Pre-filled feed name from the recommended candidate |
| `candidates` | **added** | `jsonb`, default `[]`, ranked-list shape per research §4 |
| All other columns | unchanged | |

`status` enum is unchanged: `processing → success | failed`. The `failed` state now means "no candidates at all AND no AI-backed fallback applies" (very rare with curated AI fallbacks); typical "RSS not found" cases land in `success` with an AI-only candidate list.

**Validations**:
- `candidates`: when `status: :success`, MUST be a non-empty array. When `status: :failed`, MAY be empty. When `status: :processing`, MAY be `[]`.
- Each candidate entry validates against a fixed schema (`profile_key` required and registry-known; `rank` integer; `depends_on_ai` boolean; `title` optional).

**Lifecycle**: unchanged from today; cleanup on feed save still applies (`cleanup_feed_identification(url)` — but the cleanup key becomes `(user_id, params_digest)` rather than `(user_id, url)` to handle non-URL inputs).

---

## 5. `FeedEntry` (refined)

No new columns; the existing `raw_data` JSONB carries whatever the processor needs. The contract that *every* processor populates the same set of `raw_data` keys (per `notes/profile-contracts.md`) is enforced by the `Normalizer::Base` reading them — see Post fields below.

---

## 6. `Post` (refined)

Existing fields are sufficient for RSS/XKCD. The "supplementary content" requirement (FR-015 — body + comments + images) maps to existing fields:

| Spec field | `Post` column | Notes |
|------------|---------------|-------|
| `body` | `content` | Existing; max 3000 chars |
| `supplementary` | `comments[]` | Existing array of strings (each ≤ 3000 chars). Normalizers may emit one or more. |
| `images` | `attachment_urls[]` | Existing array of URL strings |
| `source_url` | `source_url` | Existing |
| `published_at` | `published_at` | Existing |
| `uid` | `uid` | Existing; unique per feed |

**No new columns required.** The data-model change is a **convention sharpening**: every normalizer (RSS, XKCD, AI-website, AI-handle, AI-search) MUST populate `comments[]` for overflow content where applicable, where today only XKCD does. `Normalizer::Base` gains a `validate_universal_post_shape!` helper that asserts a `Post` draft is publishable.

**Validations**: existing — `enqueued` posts must have empty `validation_errors`.

---

## 7. `FeedProfile` registry (modified)

Code-only registry (research §1). Each entry's enriched shape:

```ruby
{
  display_name: "RSS Feed",
  description: "Posts from a site's RSS or Atom feed",
  input_shape: :url,                         # one of :url, :handle, :query, :any
  depends_on_ai: false,
  matcher: "ProfileMatcher::RssProfileMatcher",
  parameter_schema: {                        # JSON Schema Draft 2020-12
    "type" => "object",
    "properties" => { "url" => { "type" => "string", "format" => "uri" } },
    "required" => ["url"]
  },
  loader:     { class: "Loader::HttpLoader",        config: {} },
  processor:  { class: "Processor::RssProcessor",   config: {} },
  normalizer: { class: "Normalizer::RssNormalizer", config: {} },
  title_extractor: "TitleExtractor::RssTitleExtractor",
  output_schema: nil                         # only required for AI-using profiles
}
```

For AI profiles, `loader.config` (or `normalizer.config`) carries the LLM-specific bits:

```ruby
loader: {
  class: "Loader::LlmLoader",
  config: {
    model: "claude-opus-4-7",
    prompt_template: "...",                  # ERB or simple `{key}` substitution from feed.params
    output_schema: { ... },                  # JSON Schema for the LLM's structured output
    tools: ["web_search", "web_fetch"]       # provider-side server tools, if any
  }
}
```

**Profile-level methods** added to `FeedProfile`:
- `FeedProfile.matchers_for(input_shape)` — returns matcher classes whose `input_shape` accepts the given shape, in registration order.
- `FeedProfile.depends_on_ai?(key)` — convenience.
- `FeedProfile.parameter_schema_for(key)` — used by the form generator.
- `FeedProfile[key]` — bracket access returning the full hash.

---

## 8. Provider registry (new, code-only)

Parallel to `FeedProfile` for AI providers. Drives the credential form generator and tells `LlmClient` which RubyLLM provider key to use. RubyLLM handles provider dispatch from this string; there is no per-provider class.

```ruby
module LlmProvider
  PROVIDERS = {
    "anthropic" => {
      display_name: "Anthropic (Claude)",
      ruby_llm_provider: :anthropic,
      credential_schema: {
        "type" => "object",
        "properties" => { "api_key" => { "type" => "string", "minLength" => 10 } },
        "required" => ["api_key"]
      },
      validate_call: ->(client) { client.health_check }
    }
    # OpenAI, Gemini, OpenAI-compatible: future entries.
  }.freeze
end
```

**Why code-only**: same reasoning as `FeedProfile` — providers ship and version with the application; new providers are deployed code, not data.

---

## 9. Constitution re-check (post-design)

Re-validating against constitution v1.0.0 after this design step:

| Principle | Status |
|-----------|--------|
| I. Rails Conventions First | ✅ All routes resourceful (see `contracts/http_routes.md`); migrations are vanilla Rails; `Feed#url` becomes a method, not a column — still idiomatic. |
| II. Tests Travel With Code | ✅ Every new column gets a model spec; new state transitions are tested; the partial unique index is tested at the DB level via a duplicate-default attempt. |
| III. Atomic Commits | ✅ `tasks.md` will sequence migrations one per commit (one per new model and one per modification), each with its tests. |
| IV. Approachable UI Voice | ✅ No new model field surfaces user-facing strings other than `display_name` (user-supplied). |
| V. Observable Error Handling | ✅ `LlmUsage.outcome` enumerates the failure modes; failure-state writes go through `Rails.error.report` with `feed_id`, `profile_key`, `provider`, `stage` context. |

No new violations introduced. Complexity Tracking remains empty.
