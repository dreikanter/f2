# Pluggable Profiles: Conceptual Design for Feeder2

**Date:** 2026-05-10
**Status:** Approved (conceptual). Implementation roadmap below; per-phase specs to follow.

## Context

Feeder publishes content from external sources to FreeFeed groups on a schedule. The original "feeder1" supported a fixed catalogue of feeds maintained by one person; adding a feed required code changes, and operators (not users) controlled credentials and group access.

Feeder2 introduced multi-tenancy: users sign up, supply their own FreeFeed access tokens, and create/manage their own feeds through a web UI. The pipeline kept feeder1's three-stage shape — Loader → Processor → Normalizer — and selected stage classes through a static `FeedProfile` registry mapping a profile key to a quad of class names.

This design extends feeder2 so users (and operators) can introduce new content sources without writing code, including sources that don't expose a clean RSS/Atom feed: websites, search results, social mentions. The mechanism is to let any pipeline stage be implemented by a class that uses the LLM API internally. Such stages live next to RSS and YouTube as just another way of producing entries — same execution loop, same record types, same monitoring.

## Goal

> A feed is a recurring publication. A profile is a recipe. A user owns both. Profiles describe how to produce structured entries; everything downstream of that — scheduling, dedup, publishing, metrics — is shared infrastructure that operates on the same record types for every profile.

## Conceptual model

The system has one execution loop and three concept layers above it:

- **Publication contract.** A feed promises: on this schedule, post new items to this group with this token, don't duplicate, track health. Same for every feed regardless of source.
- **Profile (recipe).** A first-class artifact that names its three stages (Loader, Processor, Normalizer) and declares the parameters it needs from a feed. Each stage is a Ruby class; some stage classes use the LLM API internally, most don't.
- **Feed (instance).** Picks a profile and supplies values for its parameters (URL, channel ID, search query, prompt content where the profile asks for it, etc.). Owns the schedule, target group, access token, name, dedup state, and metrics.

Stage outputs are **stable, schema-conformant data**. The loader produces a list of raw items keyed by stable IDs. The processor produces `FeedEntry` records. The normalizer produces `Post` drafts. Every stage implementation must satisfy this contract — whether it parses XML, calls an HTTP endpoint, or invokes the LLM API. Schema validation is the safety boundary.

Why this model is sustainable:

1. **One execution loop.** The scheduler, dedup, publishing, metrics, and monitoring receive the same record types from every profile. New sources arrive as new stage classes plus a profile row pointing at them — not branches in core code.
2. **One unit of reuse: the profile.** Prompts, schemas, and stage choices live on profiles, not scattered across feeds.
3. **One contract per stage.** A loader is a loader, regardless of whether it uses libxml or the Anthropic API. Stages are interchangeable at the seams; the rest of the system is decoupled from how content was produced.

## Information architecture

### Entities

- **`User`** — unchanged. Owns access tokens, LLM credentials, profiles, feeds.
- **`AccessToken`** — unchanged. FreeFeed credential, used at publish.
- **`LlmCredential`** *(new)* — per-user encrypted provider key.
  - Fields: `user_id`, `provider`, `display_name`, `encrypted_key`, `last_validated_at`, `state` (`active` | `invalid` | `revoked`), timestamps.
  - The `provider` column makes the model future-proof for additional LLM providers (OpenAI, compatible endpoints): adding one is a row migration on this table, not a redesign of credential ownership, validation, or usage tracking. Anthropic is the provider supported in v1.
  - Validated on save (a small known-good provider call).
  - Has many `LlmUsage`.
- **`Profile`** — evolved from the static `FeedProfile` registry into a database row.
  - Fields: `id`, `user_id` (nullable for system-owned), `system_owned` (boolean), `key` (slug), `display_name`, `description`, `parameter_schema` (JSON Schema), `stages` (JSON), `cloned_from_id` (nullable), timestamps.
  - `stages` shape: `{ loader: {...}, processor: {...}, normalizer: {...} }`. Each stage entry has the form `{ class: "Loader::HttpLoader", config: { ... } }`. The class name resolves to a registered stage class. The config is class-specific: an HTTP loader's config might be empty (it gets its URL from feed params); an LLM stage class's config typically includes `model`, `prompt_template`, `output_schema`, and optional provider tool requests.
  - **Where prompts live.** Prompts are part of the profile's stage configuration, *as templates*. The profile's `parameter_schema` decides what is feed-controlled by interpolation into those templates. Two patterns sit naturally side by side:
    - *Prompt baked into the profile, narrow parameter:* a "Vanity Search" profile holds a fixed prompt template and exposes a single `topic` parameter. Most users get LLM-backed feeds without writing any prompt.
    - *Prompt as a profile parameter:* a "Custom LLM Normalizer" profile declares a `prompt` parameter of type `long_text`; its stage template interpolates the user's prompt directly. Users who want their own normalization rule fill in the parameter without cloning.
  - The Feed never carries a free-text "raw prompt" field. What it carries is values for whatever parameters the profile declared, which *may* include a prompt where the profile asks for one. The discipline is that prompt content always flows through a profile-declared schema.
  - Built-in profiles seeded at boot with `system_owned: true` and `user_id: null`. Their content lives in a seed file; the row is the canonical reference at runtime.
  - User-defined profiles are created by **cloning** a built-in (or another user-owned profile). Cloning copies all fields and sets `cloned_from_id`.
- **`Feed`** — same role as today.
  - Replaces `feed_profile_key` with `profile_id` (FK to Profile).
  - Adds `params` (JSONB) holding values for the chosen profile's `parameter_schema`. Validated on save against the schema.
  - Existing fields keep their meaning: `cron_expression`, `target_group`, `access_token_id`, `state`, `name`, `description`.
- **`FeedEntry`** — unchanged shape. The schema *is* the inter-stage contract. The processor that produced it is irrelevant downstream.
- **`Post`** — unchanged. Produced by the normalizer regardless of profile.
- **`LlmUsage`** *(new)* — one row per LLM stage execution.
  - Fields: `id`, `user_id`, `feed_id` (nullable for ad hoc validation), `profile_id`, `stage` (`loader` | `processor` | `normalizer`), `provider`, `model`, `input_tokens`, `output_tokens`, `cost_estimate_cents`, `outcome` (`success` | `schema_error` | `provider_error` | `budget_blocked`), `started_at`, `finished_at`.
  - Indexed by `(user_id, started_at)` and `(feed_id, started_at)` for usage rollups.
- **`Budget`** *(simple, optional)* — single row per user, monthly cap.
  - Fields: `user_id`, `monthly_cents` (nullable = no cap), `current_period_start`, `current_period_used_cents`.
  - When tripped, the system disables LLM-using feeds for the rest of the period and writes events.
- **`Event`** — already exists. Becomes the audit log for stage failures, schema violations, budget trips, profile changes affecting active feeds.

### Identifiers

`Profile.key` is a global slug for built-in profiles (`rss`, `xkcd`, etc.) used in seeds, fixtures, and admin tools. User-owned profiles are addressed by database id; their `key` is null.

## Pipeline execution

A feed firing runs the same loop as today, with one structural addition: an **execution context** object passed to stages.

The context bundles shared resources:

- **`http_client`** — for stages that fetch URLs.
- **`llm_client`** — present when the user has an active `LlmCredential` for the relevant provider. The client wraps the provider SDK and is the single chokepoint for: applying the credential, recording an `LlmUsage` row per call, validating output against an expected schema, and consulting the budget. Stages that don't use LLM ignore it.
- **`feed`, `user`, `profile`** — the records the run belongs to, for stages that need them (most don't).
- **`logger`, `event_recorder`** — for stage-level logging and audit events.

The pipeline:

1. **Loader** runs (`profile.loader_class.new(context, feed_params).call`) and returns raw items. Each item carries a stable source ID used downstream for dedup. An `Http::HttpLoader` ignores `context.llm_client`; an `Llm::WebSearchLoader` uses it.
2. **Processor** runs over the raw items and returns `FeedEntry` records. For profiles whose loader already emits structured entries (typical of LLM loaders that produce final-form items), the processor is a passthrough class.
3. **Normalizer** runs per entry and returns a `Post` draft.
4. **Publish, dedup, schedule, metrics** — unchanged paths.

LLM-using stages call `context.llm_client.call(prompt:, schema:, model:, tools:)` once per execution. The provider's server-side tools (web search, web fetch) are invoked inline within that single call: the API client makes one HTTP request out and gets one response back, with tool results already incorporated. There is no client-side tool loop, no agent SDK, no mid-run state — the loop, if any, lives entirely on the provider's side and is billed in the response's usage breakdown.

Cost tracking, budget enforcement, schema validation, and usage logging are all properties of the LLM client, not of the stage. A new LLM-using stage class only describes *how* it wants the LLM called; the surrounding policies are applied uniformly.

### Failure semantics

- **Provider error / network.** Retry once with backoff. If still failing, mark this run failed; keep the feed enabled. Event logged. Matches today's transient-failure behavior.
- **Schema validation failure.** No retry. Mark this run failed. Event logged. If the same profile produces N consecutive schema failures, surface a flag on the profile (likely a bad prompt).
- **Budget exceeded.** The LLM client checks the budget before each call. If the user's monthly cap would be crossed, the call is not made; outcome `budget_blocked` is recorded; the feed is auto-disabled for the rest of the period; the user is notified via the existing event/notifications path.
- **No malformed posts pass through.** Output is schema-validated by the LLM client before any downstream stage sees it. A response that fails validation never becomes a `Post`.

### Cost surface

- A feed's show page shows *that feed's* LLM spend (current period, last period, lifetime).
- A `/settings/llm_usage` (or similar) page aggregates by feed/profile/day.
- A budget control on the user (off by default) sets a monthly cap.
- Schema-violation rate per profile is visible — useful signal for profile authors.

## User-facing surfaces

This section describes the **conceptual surfaces** the feature requires — which pages exist, what they're for, what state they reach. It does **not** define visual design or interaction details. Visual design is iterated as wireframe mockups in a separate cycle, gating any view-code work in the corresponding implementation phase.

### Two-tier UX

**Tier 1 — Casual user.**

- "New Feed" lists profiles. Each profile has a name, short description, and a marker for whether it requires LLM credentials.
- Selecting a profile reveals a form generated from `profile.parameter_schema`. Users see "URL" or "Channel ID" or "Search query" — never the word "stage."
- If the chosen profile uses LLM stages and the user lacks an LLM credential, the existing prerequisite-gate pattern kicks in: a clear "Add a Claude API key to use this profile" call to action, mirroring the existing access-token gate at `/feeds/new`.

**Tier 2 — Power user.**

- A profile's page exposes a "Clone" action.
- The clone editor has three sections:
  - **Parameter schema** — declare what the profile asks of feeds (name, type, label, validation).
  - **Stages** — for each of `loader`, `processor`, `normalizer`, pick a stage class from the registry and provide its config (for LLM-using classes that means model, prompt template, output schema, and any provider tool requests).
  - **Test panel** — run the profile against sample input or a real URL, see the staged output and a token/cost estimate before saving.
- Saving creates a user-owned profile assignable to feeds.
- Editing a profile **affects every feed using it**. The editor warns about this and shows the affected feed count.

### Settings and monitoring surfaces

- **`/settings/llm_credentials`** — list, add, validate, revoke. Same shape as access tokens.
- **`/settings/llm_usage`** — usage and budget. Default empty until a credential exists.
- **Feed show page** — adds an LLM usage panel when the feed's profile uses LLM stages. Recent runs, schema-violation count, current-period cost.
- **Profile pages** — show usage and reliability across all feeds using the profile.

## Migration from current state

- The current `FeedProfile` is a Ruby class wrapping a frozen `PROFILES` hash with two entries (`rss`, `xkcd`). Migration moves this into seeded rows of the new `Profile` table; the existing class either becomes a thin adapter for legacy callers during transition or is deleted at the end of the migration phase.
- `Feed.feed_profile_key` becomes `Feed.profile_id`; a backfill maps each existing key to the seeded row id. `feed_profile_key` is removed at the end of the phase, not during.
- `Feed.params` is added empty for existing feeds. Whether the URL moves into `params.url` (under the seeded RSS profile's `{ url: string }` schema) or stays a top-level Feed field for backward compatibility is decided in the phase 1 sub-spec; both paths preserve current behavior.

## Implementation roadmap

Each phase produces a verifiable, reviewable result. Phases are sized to land in independent PRs (target ~500–1500 LOC of substantive change per phase, excluding generated migrations and tests). Each phase that touches UI is preceded by a wireframe pass.

**Phase 1 — Profile as data.** Migrate `FeedProfile` from class registry to a `profiles` table with seeded rows for `rss` and `xkcd`. Add `parameter_schema`, `stages`, `system_owned`, `user_id`, `cloned_from_id`. Add `Feed.profile_id` and `Feed.params`; backfill from `feed_profile_key` and `url`. Existing stage classes keep their interfaces. No behavior change. *Verifiable:* full test suite green; manual test refresh of an RSS feed produces the same posts as before.

**Phase 2 — LLM credentials.** Add `LlmCredential` model, encryption at rest, validation-on-save. Add `/settings/llm_credentials` UI (gated on wireframe pass). No LLM execution yet. *Verifiable:* a user can add, validate, and revoke an Anthropic credential.

**Phase 3 — Execution context + first LLM-using stage class.** Introduce the execution context plumbing (resources passed into stages) along with the LLM client that owns provider calls, schema validation, and usage logging. Ship one built-in LLM-using stage class and a profile that uses it end-to-end. The lowest-risk choice is an LLM-backed normalizer (RSS loader/processor + LLM normalizer for sanitization/length-fitting): the loader path is unchanged and the LLM is exercised on a small, well-scoped transformation. *Verifiable:* a user can create a feed using this profile and see properly normalized posts; `LlmUsage` rows record token counts and cost estimates accurately.

**Phase 4 — Budget enforcement.** Add `Budget`. Pre-call check in the LLM client. Disable-on-trip path with events and notifications. Surface usage in the feed show page and a `/settings/llm_usage` page (gated on wireframe pass). *Verifiable:* setting a low cap and exceeding it disables the feed and notifies the user; usage UI displays accurate aggregates.

**Phase 5 — LLM-using loader stage classes.** Implement loader classes that produce structured entries via the LLM API (using provider server-side web search and web fetch tools). Ship "Web Search Aggregator" and "Website Without RSS" built-in profiles. *Verifiable:* a user creates a feed for a non-RSS site and gets posts from it.

**Phase 6 — Profile authoring (advanced UX).** Clone-and-edit flow. Editor for parameter schema, stages, and a test panel. Affected-feeds warning on save (gated on wireframe pass — this is the most UX-heavy phase and should be the most carefully iterated). *Verifiable:* a power user can clone a built-in, change a prompt, and use the result on a feed.

**Phase 7 — Polish and observability.** Schema-violation rate per profile, profile health flags, usage trend visualizations, audit-log linking from feeds to events. *Verifiable:* operator and user can answer "why is this feed failing" without reading code.

Each phase ends with merged tests, a green CI, and an updated migration story. Phases 2–7 each begin with a small sub-spec covering surface-level details (model fields, exact UI states) so this spec doesn't have to predict everything.

## Open questions (deferred to per-phase sub-specs)

- Whether the processor for an LLM-loader profile is a passthrough class or skipped by configuration. Decide in phase 5.
- Exact JSON Schema dialect for `parameter_schema` (Draft 7 vs. 2020-12). Decide in phase 1.
- Encryption strategy for `LlmCredential.encrypted_key`. Likely Rails' built-in `encrypts`. Confirm in phase 2.
- Whether profile editing should snapshot to a version (and feeds opt in to upgrade) once user-defined profiles are in real use. Revisit after phase 6.
