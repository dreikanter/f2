# Pluggable Profiles: Conceptual Design for Feeder2

**Date:** 2026-05-10
**Status:** Approved (conceptual). Implementation roadmap below; per-phase specs to follow.
**Supersedes:** `docs/specs/feeds-management.md`

## Context

Feeder publishes content from external sources to FreeFeed groups on a schedule. The original "feeder1" supported a fixed catalogue of feeds maintained by one person; adding a feed required code changes, and operators (not users) controlled credentials and group access.

Feeder2 introduced multi-tenancy: users sign up, supply their own FreeFeed access tokens, and create/manage their own feeds through a web UI. The pipeline kept feeder1's three-stage shape — Loader → Processor → Normalizer — and selected stage classes through a static `FeedProfile` registry mapping a profile key to a quad of class names.

This design extends feeder2 along one axis: **let users (and operators) introduce new content sources without writing code**, including sources that don't expose a clean RSS/Atom feed (websites, search results, social mentions). The mechanism is a single structured LLM call substituted for any pipeline stage. The design's goal is to fit this new capability into the existing model without forking it into a parallel "LLM mode" that drifts.

## Goal

> A feed is a recurring publication. A profile is a recipe. A user owns both. Profiles describe how to produce structured entries; everything downstream of that — scheduling, dedup, publishing, metrics — is shared infrastructure that doesn't know or care which kind of stage produced the data.

## Non-goals (v1)

- **Bounded LLM agents with tool loops.** Stages run a single structured call. Multi-turn agents are a possible future stage type but introduce significant new surface (tool sandboxing, mid-run cost control, prompt-injection defense) and are explicitly out.
- **Profile sharing / marketplace.** The data model accommodates it later (visibility flag); no UI in v1.
- **Per-feed per-stage overrides** on top of profiles. Reuse runs through profiles. If a user wants a different prompt, they clone the profile.
- **Streaming output, multi-provider failover, automated A/B prompt testing.** Future, if ever.
- **A second LLM provider.** The credential model is polymorphic (provider + key) so a second provider is a row migration, not a redesign — but only Anthropic ships in v1.

## Conceptual model

The system has one execution loop and three concept layers above it:

- **Publication contract.** A feed promises: on this schedule, post new items to this group with this token, don't duplicate, track health. Same for every feed regardless of source.
- **Profile (recipe).** A first-class artifact that names its three stages and declares the parameters it needs from a feed. Each stage is implemented by either a **canonical Ruby class** or a **single structured LLM call**.
- **Feed (instance).** Picks a profile and supplies values for its parameters (URL, channel ID, search query, prompt overrides, etc.). Owns the schedule, target group, access token, name, dedup state, and metrics.

Stage outputs are **stable, schema-conformant data**. The loader produces a list of raw items keyed by stable IDs. The processor produces `FeedEntry` records. The normalizer produces `Post` drafts. Any stage implementation — canonical or LLM — must satisfy this contract. Schema validation is the safety boundary.

Why this model is sustainable:

1. **One execution loop.** The scheduler, dedup, publishing, metrics, and monitoring receive the same record types regardless of profile. New sources arrive as profile rows, not branches in core code.
2. **No parallel "LLM mode."** LLM is a stage implementation alongside canonical classes. The system can't drift into two modes because there is no mode.
3. **One unit of reuse: the profile.** Prompts, schemas, and stage choices live on profiles, not scattered across feeds.

## Information architecture

### Entities

- **`User`** — unchanged. Owns access tokens, LLM credentials, profiles, feeds.
- **`AccessToken`** — unchanged. FreeFeed credential, used at publish.
- **`LlmCredential`** *(new)* — per-user encrypted provider key.
  - Fields: `user_id`, `provider` (`anthropic` in v1), `display_name`, `encrypted_key`, `last_validated_at`, `state` (`active` | `invalid` | `revoked`), timestamps.
  - Validated on save (a small known-good provider call).
  - Has many `LlmUsage`.
- **`Profile`** — evolved from the static `FeedProfile` registry into a database row.
  - Fields: `id`, `user_id` (nullable for system-owned), `system_owned` (boolean), `key` (slug), `display_name`, `description`, `parameter_schema` (JSON Schema), `stages` (JSON), `cloned_from_id` (nullable), timestamps.
  - `stages` shape: `{ loader: {...}, processor: {...}, normalizer: {...} }`. Each stage entry is either:
    - **canonical:** `{ kind: "canonical", impl: "Loader::HttpLoader" }` (impl resolves to a registered class).
    - **llm:** `{ kind: "llm", model: "claude-...", prompt_template: "...", output_schema: {...}, tools: [...] }`. Tools in v1 limited to provider-native features (e.g., web search) — no custom tool definitions.
  - Built-in profiles seeded at boot with `system_owned: true` and `user_id: null`. Their schema is in code (a seed file), but the row is canonical.
  - User-defined profiles created by **cloning** a built-in (or another user-owned profile). Cloning copies all fields and sets `cloned_from_id`.
- **`Feed`** — same role as today.
  - Replaces `feed_profile_key` with `profile_id` (FK to Profile).
  - Adds `params` (JSONB) holding values for the chosen profile's `parameter_schema`. Validated on save against the schema.
  - Existing fields keep their meaning: `cron_expression`, `target_group`, `access_token_id`, `state`, `name`, `description`.
- **`FeedEntry`** — unchanged shape. The schema *is* the inter-stage contract. The loader/processor that produced it is irrelevant downstream.
- **`Post`** — unchanged. Produced by either canonical or LLM normalizer.
- **`LlmUsage`** *(new)* — one row per LLM stage execution.
  - Fields: `id`, `user_id`, `feed_id` (nullable for ad hoc validation), `profile_id`, `stage` (`loader` | `processor` | `normalizer`), `provider`, `model`, `input_tokens`, `output_tokens`, `cost_estimate_cents`, `outcome` (`success` | `schema_error` | `provider_error` | `budget_blocked`), `started_at`, `finished_at`.
  - Indexed by `(user_id, started_at)` and `(feed_id, started_at)` for usage rollups.
- **`Budget`** *(simple, optional)* — single row per user, monthly cap.
  - Fields: `user_id`, `monthly_cents` (nullable = no cap), `current_period_start`, `current_period_used_cents`.
  - When tripped, the system disables LLM-using feeds for the rest of the period and writes events.
- **`Event`** — already exists. Becomes the audit log for stage failures, schema violations, budget trips, profile changes affecting active feeds.

### Notable absences and why

- **No `FeedKind` / `PromptFeed` / `SourceFeed`.** One Feed model. Polymorphism is on the profile.
- **No prompt fields on Feed.** Prompts live on the profile. Avoids "prompts scattered across feeds."
- **No agent runtime, no sandbox VM.** Shape X (single structured call) means no tool loop, no mid-run state. The LLM call itself only sees the rendered prompt; the runner around it owns all I/O (provider call, schema validation, usage recording).
- **No identity in `Profile.key` for user-owned profiles.** `key` is a global slug for built-ins; user-owned profiles use the database id.

## Pipeline execution

A feed firing runs the same loop as today, with a small refactor:

1. **Stage dispatch** goes through a single `StageRunner` interface with two implementations:
   - `CanonicalRunner.call(stage_config, input)` — instantiates the configured class and calls it.
   - `LlmRunner.call(stage_config, input, credential, budget)` — renders the prompt template with the input, calls the provider, validates the response against `output_schema`, writes an `LlmUsage` row, returns parsed output.
2. **Loader** produces a list of raw items. Each item carries a stable source ID used downstream for dedup.
3. **Processor** produces `FeedEntry` records. (For LLM-loader profiles whose loader already emits structured entries, the processor is a passthrough.)
4. **Normalizer** produces `Post` drafts.
5. **Publish, dedup, schedule, metrics** — unchanged paths.

LLM stage execution is **synchronous within the runner** (no agentic looping), but the runner is invoked from background jobs the same way canonical stages are. From the scheduler's perspective there is no difference.

### Failure semantics

- **Provider error / network.** Retry once with backoff. If still failing, mark this run failed; keep the feed enabled. Event logged. Matches today's transient-failure behavior.
- **Schema validation failure.** No retry. Mark this run failed. Event logged. If the same profile produces N consecutive schema failures, surface a flag on the profile (the user may have a bad prompt).
- **Budget exceeded.** Pre-flight check before each LLM call. If the user's monthly cap would be crossed, the call is not made; outcome `budget_blocked` is recorded; the feed is auto-disabled for the rest of the period; user is notified via the existing event/notifications path.
- **No silent malformed posts.** Output is schema-validated before any downstream stage sees it. Failed validation never reaches `Post`.

### Cost surface

- A feed's show page shows *that feed's* LLM spend (current period, last period, lifetime).
- A `/settings/llm_usage` (or similar) page aggregates by feed/profile/day.
- A budget control on the user (off by default) sets a monthly cap.
- Schema-violation rate per profile is visible — useful signal for profile authors.

## User-facing surfaces

### Two-tier UX

**Tier 1 — Casual user.**

- "New Feed" lists profiles. Each profile has a name, short description, and a marker for whether it requires LLM credentials.
- Selecting a profile reveals a form generated from `profile.parameter_schema`. Users see "URL" or "Channel ID" or "Search query" — never the word "stage."
- If the chosen profile uses LLM stages and the user lacks an LLM credential, the existing prerequisite-gate pattern kicks in: a clear "Add a Claude API key to use this profile" call to action, mirroring the existing access-token gate at `/feeds/new`.

**Tier 2 — Power user.**

- A profile's page exposes a "Clone" action.
- The clone editor has three sections:
  - **Parameter schema** — declare what the profile asks of feeds (name, type, label, validation).
  - **Stages** — for each of `loader`, `processor`, `normalizer`, pick a canonical class from a registry, or define an LLM stage (model, prompt template, output schema, optional provider tools).
  - **Test panel** — run the profile against sample input or a real URL, see the staged output and a token/cost estimate before saving.
- Saving creates a user-owned profile assignable to feeds.
- Editing a profile **affects every feed using it**. The editor warns about this and shows the affected feed count. (Snapshot-on-enable can be added later if this becomes a real foot-gun; not in v1.)

### Settings and monitoring surfaces

- **`/settings/llm_credentials`** — list, add, validate, revoke. Same shape as access tokens.
- **`/settings/llm_usage`** — usage and budget. Default empty until a credential exists.
- **Feed show page** — adds an LLM usage panel when the feed's profile uses LLM stages. Recent runs, schema-violation count, current-period cost.
- **Profile pages** — show usage and reliability across all feeds using the profile.

### UX iteration gate

Every phase below that touches user-facing UI is **gated on a separate wireframe pass**. Before a phase's UI work begins, static mockups for the affected surfaces are produced and reviewed (alternatives considered, structure agreed). Wireframe iteration is its own loop, with its own approval. This spec does not freeze the visual design.

## Migration from current state

- The current `FeedProfile` is a Ruby class wrapping a frozen `PROFILES` hash with two entries (`rss`, `xkcd`). Migration moves this into seeded rows of the new `Profile` table; the existing class either becomes a thin adapter for legacy callers during transition or is deleted at the end of the migration phase.
- `Feed.feed_profile_key` becomes `Feed.profile_id`; a backfill maps each existing key to the seeded row id. `feed_profile_key` is removed at the end of the phase, not during.
- `Feed.params` is added empty for existing feeds. Whether the URL moves into `params.url` (under the seeded RSS profile's `{ url: string }` schema) or stays a top-level Feed field for backward compatibility is decided in the phase 1 sub-spec; both paths preserve current behavior.
- The old spec at `docs/specs/feeds-management.md` is replaced with a redirect note pointing here as part of phase 1.

## Implementation roadmap

Each phase produces a verifiable, reviewable result. Phases are sized to land in independent PRs (target ~500–1500 LOC of substantive change per phase, excluding generated migrations and tests). Each phase that touches UI is preceded by a wireframe pass.

**Phase 0 — Old spec retired (this spec only).** Replace `docs/specs/feeds-management.md` with a brief redirect note pointing to this design. No code changes. *Verifiable:* the old spec no longer documents future work; main branch reflects only the active design.

**Phase 1 — Profile as data.** Migrate `FeedProfile` from class registry to a `profiles` table with seeded rows for `rss` and `xkcd`. Add `parameter_schema`, `stages`, `system_owned`, `user_id`, `cloned_from_id`. Add `Feed.profile_id` and `Feed.params`; backfill from `feed_profile_key` and `url`. No behavior change. *Verifiable:* full test suite green; manual test refresh of an RSS feed produces the same posts as before.

**Phase 2 — StageRunner interface.** Introduce `StageRunner` with `CanonicalRunner` only. Refactor the existing pipeline (loader/processor/normalizer dispatch) to flow through the runner. *Verifiable:* tests green; the pipeline has one code path through which all stages run.

**Phase 3 — LLM credentials.** Add `LlmCredential` model, encryption at rest, validation-on-save. Add `/settings/llm_credentials` UI (gated on wireframe pass). No LLM execution yet. *Verifiable:* a user can add, validate, and revoke an Anthropic credential.

**Phase 4 — LLM stage runner + first LLM-flavored profile.** Implement `LlmRunner` (prompt rendering, provider call, schema validation, `LlmUsage` write). Ship one built-in LLM profile that exercises the path end-to-end — the lowest-risk choice is a normalizer-only LLM profile (RSS canonical loader/processor + LLM normalizer for sanitization/length-fitting). *Verifiable:* a user can create a feed using this profile and see properly normalized posts; usage rows are recorded.

**Phase 5 — Budget enforcement.** Add `Budget`. Pre-flight check in `LlmRunner`. Disable-on-trip path with events and notifications. Surface usage in feed show page and a `/settings/llm_usage` page (gated on wireframe pass). *Verifiable:* setting a low cap and exceeding it disables the feed and notifies the user; usage UI displays accurate aggregates.

**Phase 6 — LLM-loader profiles.** Implement an LLM loader stage type. Ship "Web Search Aggregator" and "Website Without RSS" built-in profiles. *Verifiable:* a user creates a feed for a non-RSS site and gets posts from it.

**Phase 7 — Profile authoring (advanced UX).** Clone-and-edit flow. Editor for parameter schema, stages, and a test panel. Affected-feeds warning on save (gated on wireframe pass — this is the most UX-heavy phase and should be the most carefully iterated). *Verifiable:* a power user can clone a built-in, change a prompt, and use the result on a feed.

**Phase 8 — Polish and observability.** Schema-violation rate per profile, profile health flags, usage trend visualizations, audit-log linking from feeds to events. *Verifiable:* operator and user can answer "why is this feed failing" without reading code.

Each phase ends with merged tests, a green CI, and an updated migration story. Phases 3–8 each begin with a small sub-spec covering surface-level details (model fields, exact UI states) so the conceptual spec doesn't have to predict everything.

## Open questions (deferred to per-phase sub-specs)

- Whether the canonical processor for an LLM-loader profile is "passthrough" (a no-op class) or "implicit" (the runner skips it). Either works; choose in phase 6.
- Exact JSON Schema dialect for `parameter_schema` (Draft 7 vs. 2020-12). Choose in phase 1.
- Encryption strategy for `LlmCredential.encrypted_key`. Likely Rails' built-in `encrypts`. Confirm in phase 3.
- Whether profile editing should snapshot to a version (and feeds opt in to upgrade) once user-defined profiles are in real use. Revisit after phase 7.
