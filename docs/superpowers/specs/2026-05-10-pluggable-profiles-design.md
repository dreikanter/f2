# Pluggable Profiles: Conceptual Design for Feeder2

**Date:** 2026-05-10
**Status:** Approved (conceptual). Implementation roadmap below; per-phase specs to follow.

## Context

Feeder publishes content from external sources to FreeFeed groups on a schedule. The original "feeder1" supported a fixed catalogue of feeds maintained by one person; adding a feed required code changes, and operators (not users) controlled credentials and group access.

Feeder2 introduced multi-tenancy: users sign up, supply their own FreeFeed access tokens, and create/manage their own feeds through a web UI. The pipeline kept feeder1's three-stage shape — Loader → Processor → Normalizer — and selected stage classes through a static `FeedProfile` registry mapping a profile key to a quad of class names.

This design extends feeder2 so users (and operators) can introduce new content sources without writing code, including sources that don't expose a clean RSS/Atom feed: websites, search results, social mentions. The mechanism is to let any pipeline stage be implemented by a class that uses the LLM API internally. Such stages live next to RSS and YouTube as just another way of producing entries — same execution loop, same record types, same monitoring.

## Goal

> A feed is a recurring publication a user owns. A profile is a recipe the system ships in code. Profiles describe how to produce structured entries; everything downstream of that — scheduling, dedup, publishing, metrics — is shared infrastructure that operates on the same record types for every profile.

## Conceptual model

The system has one execution loop and three concept layers above it:

- **Publication contract.** A feed promises: on this schedule, post new items to this group with this token, don't duplicate, track health. Same for every feed regardless of source.
- **Profile (recipe).** A system-curated record that names three stages (Loader, Processor, Normalizer), supplies their per-stage configuration where applicable, and declares the parameters it asks of feeds. Profiles are defined in code (an enriched `FeedProfile` registry), not in the database — they ship and evolve with the application. Each stage is a Ruby class; some stage classes use the LLM API internally, most don't.
- **Feed (instance).** Picks a profile (by key) and supplies values for its parameters (URL, channel ID, search query, prompt content where the profile asks for it, etc.). Owns the schedule, target group, access token, name, dedup state, and metrics.

Stage outputs satisfy stable contracts:

- **Loader** returns raw data for the feed (an HTTP body, a parsed JSON array, etc.).
- **Processor** splits the raw data into individual items and returns an array of unsaved `FeedEntry` instances, each carrying a `uid` (dedup key), `published_at`, and a per-item `raw_data` hash. Persistence and dedup happen in the surrounding workflow.
- **Normalizer** turns one `FeedEntry` into a `Post` draft.

Every stage implementation must satisfy its contract — whether it parses XML, calls an HTTP endpoint, or invokes the LLM API. Schema validation (for LLM responses) is the safety boundary at the seams that need one.

Why this model is sustainable:

1. **One execution loop.** The scheduler, dedup, publishing, metrics, and monitoring receive the same record types from every profile. New sources arrive as new stage classes plus a profile row pointing at them — not branches in core code.
2. **One unit of reuse: the profile.** Per-stage configuration, prompts, and schemas live on profile rows, not scattered across feeds.
3. **One contract per stage.** A loader is a loader, regardless of whether it uses libxml or the Anthropic API. Stages are interchangeable at the seams; the rest of the system is decoupled from how content was produced.

The pipeline always has exactly three stages — Loader, Processor, Normalizer. They are the model's structural seams, not a configurable list. There is no "stages array."

## Information architecture

### Entities

- **`User`** — unchanged. Owns access tokens, LLM credentials, feeds. (Profiles are system-owned in v1.)
- **`AccessToken`** — unchanged. FreeFeed credential, used at publish.
- **`LlmCredential`** *(new)* — per-user encrypted provider key.
  - Fields: `user_id`, `provider`, `display_name`, `encrypted_key`, `last_validated_at`, `state` (`active` | `invalid` | `revoked`), timestamps.
  - The `provider` column makes the model future-proof for additional LLM providers (OpenAI, compatible endpoints): adding one is a row migration on this table, not a redesign of credential ownership, validation, or usage tracking. Anthropic is the provider supported in v1.
  - Validated on save (a small known-good provider call).
  - Has many `LlmUsage`.
- **`FeedProfile`** *(registry, not a table)* — an enriched version of the existing Ruby registry. Each entry has:
  - `key` (slug, unique) — used by `Feed.feed_profile_key`.
  - `display_name`, `description` — for the feed-creation UI.
  - `parameter_schema` (JSON Schema) — declares what values feeds must supply; drives form generation.
  - `loader_class`, `loader_config` — class name string and class-specific config (typically empty for canonical stages; for LLM-using stages, carries `model`, `prompt_template`, `output_schema`, and any provider tool requests).
  - `processor_class`, `processor_config` — same shape.
  - `normalizer_class`, `normalizer_config` — same shape.
  - `requires_llm?` — derived (true if any stage's class is LLM-using).
  - The registry can be a Ruby constant, a small DSL, or YAML files in `config/profiles/`. Phase 1 picks the form. The point is that profiles are **deployed code**, not data: they evolve atomically with the stage classes that consume them.
  - **Where prompts live.** When a profile uses an LLM stage, the prompt is part of that stage's `*_config` as a template string. The profile's `parameter_schema` decides what feed-supplied values are interpolated into the template. Built-in profiles use one of two patterns, depending on what the profile is for:
    - *Prompt baked in, narrow parameter:* a "Twitter via search" profile holds a fixed prompt template and exposes only a `username` parameter. Users get an LLM-backed feed without writing any prompt.
    - *Prompt as a parameter:* a "Custom LLM normalizer" profile declares a `user_prompt` parameter of type `long_text`; its stage template wraps the user's prompt. Users who want their own normalization rule fill in the parameter when configuring the feed.
  - The Feed never carries a free-text "raw prompt" field. It carries values for whatever parameters the profile declared, which *may* include a prompt-typed parameter when the profile is designed to accept one. Prompt content always flows through a profile-declared schema.
- **`Feed`** — same role as today.
  - Keeps `feed_profile_key` as the reference to the profile registry entry.
  - Adds `params` (JSONB) holding values for the chosen profile's `parameter_schema`. Validated on save against the schema looked up in the registry.
  - Existing fields keep their meaning: `cron_expression`, `target_group`, `access_token_id`, `state`, `name`, `description`.
- **`FeedEntry`** — unchanged shape. The schema *is* the inter-stage contract. The processor that produced it is irrelevant downstream.
- **`Post`** — unchanged. Produced by the normalizer regardless of profile.
- **`LlmUsage`** *(new)* — one row per LLM stage execution.
  - Fields: `id`, `user_id`, `feed_id` (nullable for ad hoc validation), `profile_key` (string, references the registry), `stage` (`loader` | `processor` | `normalizer`), `provider`, `model`, `input_tokens`, `output_tokens`, `cost_estimate_cents`, `outcome` (`success` | `schema_error` | `provider_error`), `started_at`, `finished_at`.
  - Indexed by `(user_id, started_at)` and `(feed_id, started_at)` for usage rollups; `profile_key` is grouped by string for per-profile rollups.
- **`Event`** — already exists. Becomes the audit log for stage failures and schema violations.

## Pipeline execution

A feed firing runs the same loop as today. Stage classes keep their existing constructor signatures: the loader receives the feed, the processor receives the feed and the loader's raw data, the normalizer receives a feed entry. From a feed, a stage reaches the user (`feed.user`), the profile registry entry (`FeedProfile[feed.feed_profile_key]`), and any per-stage configuration (`profile.loader_config` and friends).

The pipeline:

1. **Loader** runs — the loader class named by `profile.loader_class`, instantiated with the feed (and the loader's `*_config` from the registry where applicable). It returns raw data: typically an HTTP response body, or, for LLM loaders, a parsed structured payload (e.g., a JSON array).
2. **Processor** receives the loader's raw data and returns an array of unsaved `FeedEntry` instances, each populated with `feed`, `uid` (the dedup key), `published_at`, and a per-item `raw_data` hash. For profiles whose loader already emits structured items, the processor is a passthrough class that maps each item into a `FeedEntry` instance without parsing.
3. The surrounding workflow persists new `FeedEntry` instances (skipping duplicates by `uid`) and feeds new ones into the normalizer.
4. **Normalizer** runs per entry and returns a `Post` draft.
5. **Publish, schedule, metrics** — unchanged paths.

### LLM client

LLM-using stages call a single `LlmClient` service keyed to the feed's user. The stage doesn't talk to the provider SDK directly; it asks the client for a structured result. The client is the chokepoint that:

- Resolves the user's active `LlmCredential` for the relevant provider.
- Adapts the request to the provider (structured-output mechanism, tool requests).
- Validates the response against the supplied output schema.
- Writes an `LlmUsage` row with feed/profile/stage metadata, regardless of outcome.

Budget enforcement (caps that pause feeds when crossed) is a deliberate v1 omission — see "Future scope." For v1, the client tracks usage so users can see what they've spent; spending controls are a follow-up.

Pseudocode at the call site:

```ruby
result = LlmClient.for(feed).call(
  stage:           :normalizer,
  model:           config[:model],
  prompt:          rendered_prompt,
  output_schema:   config[:output_schema],
  tools:           config[:tools]
)
```

A stage that doesn't use the LLM never instantiates the client. There is no shared "context" object passed around — the LLM client is a service stages reach for when they need it, the same way they reach for `HttpClient` today.

### How LLM stages call the provider

The `LlmClient` adapts the request to the chosen provider:

- **Anthropic** doesn't have a single `response_format: json_schema` parameter. The standard pattern for guaranteed structured output is to declare a tool with the desired schema as its `input_schema` and force the model to call it via `tool_choice: {type: "tool", name: "..."}`. The tool's `input` becomes the structured response. Provider-native server tools (web search, web fetch) are added to the same `tools` array; the provider runs them server-side inside the same API call.
- **OpenAI** uses `response_format: {type: "json_schema", json_schema: {strict: true, schema: ...}}` directly, plus its own server-managed search/fetch tools where applicable.
- The LLM client owns these provider-specific shapes. Stage classes only declare *what* they want (a prompt template, an output schema, a list of tool names); they don't know which mechanism the provider uses to enforce structure.

Either way, it's one HTTP request out and one response back, with any tool results already incorporated. There is no client-side tool loop, no agent SDK, no mid-run state — the loop lives entirely on the provider's side and is billed in the response's usage breakdown.

Cost tracking, budget enforcement, schema validation, and usage logging are all properties of the LLM client. A new LLM-using stage class only describes *how* it wants the LLM called; the surrounding policies are applied uniformly.

### Failure semantics

- **Provider error / network.** Retry once with backoff. If still failing, mark this run failed; keep the feed enabled. Event logged. Matches today's transient-failure behavior.
- **Schema validation failure.** No retry. Mark this run failed. Event logged. If the same profile produces N consecutive schema failures, surface a flag on the profile (likely a bad prompt).
- **No malformed posts pass through.** Output is schema-validated by the LLM client before any downstream stage sees it. A response that fails validation never becomes a `Post`.

### Cost surface

- A feed's show page shows *that feed's* LLM spend (current period, last period, lifetime).
- A `/settings/llm_usage` (or similar) page aggregates by feed/profile/day.
- Schema-violation rate per profile is visible to operators — useful signal for tuning built-in prompts.

## User-facing surfaces

This section describes the **conceptual surfaces** the feature requires — which pages exist, what they're for, what state they reach. It does **not** define visual design or interaction details. Visual design is iterated as wireframe mockups in a separate cycle, gating any view-code work in the corresponding implementation phase.

### Feed creation and editing

- "New Feed" lists profiles. Each profile has a name, short description, and a marker for whether it requires LLM credentials.
- Selecting a profile reveals a form generated from `profile.parameter_schema`. Users see "URL" or "Channel ID" or "Search query" — never the word "stage."
- If the chosen profile uses LLM stages and the user lacks an LLM credential, a prerequisite gate kicks in: "Add a Claude API key to use this profile," mirroring the existing access-token gate at `/feeds/new`.
- Editing a feed lets the user change parameter values within the constraints of the chosen profile's schema. The profile itself is not editable (and switching a feed to a different profile is not supported in v1, because it would require re-validating dedup history).

### Settings and monitoring

- **`/settings/llm_credentials`** — list, add, validate, revoke. Same shape as access tokens.
- **`/settings/llm_usage`** — usage rollups per feed/profile/day. Default empty until a credential exists.
- **Feed show page** — adds an LLM usage panel when the feed's profile uses LLM stages. Recent runs, schema-violation count, current-period cost.
- **Operator-only profile views** — the maintainer can review aggregate usage and reliability across feeds for each system profile, useful for tuning prompts and identifying regressions. Not exposed to end users in v1.

## Migration from current state

- The current `FeedProfile` is a Ruby class wrapping a frozen `PROFILES` hash with two entries (`rss`, `xkcd`). It gains `description`, `parameter_schema`, and the three `*_config` slots; the two existing profiles get filled in. No new tables.
- `Feed.feed_profile_key` keeps its meaning. `Feed.params` (JSONB) is added; it is empty for existing feeds, and validated against `FeedProfile[feed_profile_key].parameter_schema` on save.
- Whether `Feed.url` moves into `params.url` (under the RSS profile's `{ url: string }` schema) or stays a top-level Feed column for backward compatibility is decided in the phase 1 sub-spec; both paths preserve current behavior.

## Implementation roadmap

Each phase produces a verifiable, reviewable result. Phases are sized to land in independent PRs (target ~500–1500 LOC of substantive change per phase, excluding generated migrations and tests). Each phase that touches UI is preceded by a wireframe pass.

**Phase 1 — Enrich profile registry; add `Feed.params`.** Extend the existing `FeedProfile` registry with `description`, `parameter_schema`, and per-stage `*_config` slots. Pick the form (Ruby constant, DSL, or YAML files in `config/profiles/`). Update the two existing profiles (`rss`, `xkcd`) to the richer shape. Add `Feed.params` (JSONB) with on-save schema validation. No new tables. Existing stage classes keep their interfaces. No behavior change. *Verifiable:* full test suite green; manual test refresh of an RSS feed produces the same posts as before.

**Phase 2 — LLM credentials.** Add `LlmCredential` model, encryption at rest, validation-on-save. Add `/settings/llm_credentials` UI (gated on wireframe pass). No LLM execution yet. *Verifiable:* a user can add, validate, and revoke an Anthropic credential.

**Phase 3 — `LlmClient` + first LLM-using stage class.** Build the `LlmClient` service: provider call (Anthropic in v1), structured-output enforcement via forced tool-use, schema validation, `LlmUsage` write. Add `LlmUsage` model. Ship one built-in LLM-using stage class and a profile that uses it end-to-end. The lowest-risk choice is an LLM-backed normalizer (RSS loader/processor + LLM normalizer for sanitization/length-fitting): the loader path is unchanged and the LLM is exercised on a small, well-scoped transformation. *Verifiable:* a user can create a feed using this profile and see properly normalized posts; `LlmUsage` rows record token counts and cost estimates accurately.

**Phase 4 — Usage visibility.** Surface LLM usage in the feed show page (per-feed lifetime/current-period spend) and a `/settings/llm_usage` page with rollups by feed/profile/day (gated on wireframe pass). No spending caps; this phase makes consumption visible so users can decide what they want to do about it. *Verifiable:* a user can see accurate per-feed and aggregate token/cost numbers after running LLM-backed feeds for a while.

**Phase 5 — LLM-using loader stage classes.** Implement loader classes that produce structured items via the LLM API (using provider server-side web search and web fetch tools), plus a `Processor::PassthroughProcessor` that maps loader output to `FeedEntry` instances. Ship at least one built-in profile that exercises the path end-to-end (e.g., "Twitter via search" or "Website without RSS"). *Verifiable:* a user creates a feed for a non-RSS source and gets posts from it.

**Phase 6 — Polish and observability.** Schema-violation rate per profile, profile health flags, usage trend visualizations, audit-log linking from feeds to events. *Verifiable:* operator and user can answer "why is this feed failing" without reading code.

Each phase ends with merged tests, a green CI, and an updated migration story. Phases 2–6 each begin with a small sub-spec covering surface-level details (model fields, exact UI states) so this spec doesn't have to predict everything.

## Future scope (not in v1)

- **Budget enforcement.** Spending caps that pause LLM-using feeds when crossed, with pre-call checks and user notifications. Designed as a thin layer over the v1 usage tracking; the `LlmClient` already writes one row per call, so a per-period sum is easy to compare against a cap. Tracked separately so the v1 release isn't blocked on the policy/UX of caps. *Tracked in:* [#359](https://github.com/dreikanter/f2/issues/359).
- **User-authored profiles.** A clone-and-edit flow where power users create their own profiles by adapting built-in ones. Adds a parameter-schema editor, a stage editor, prompt and output-schema editing, a test panel, and the validation surface those imply. This is the moment the profile registry migrates from code into a `profiles` database table: a seed task copies the in-code registry into rows; user-authored profiles are inserted as rows with `user_id`/`system_owned`/`cloned_from_id`; `Feed.feed_profile_key` is replaced by `Feed.profile_id`; `LlmUsage.profile_key` becomes `LlmUsage.profile_id`. The existing stage classes don't change. Revisit once v1 is in real use and there's evidence that built-in profiles can't cover the demand.
- **Profile sharing.** Visibility flag on user-authored profiles, fork count, marketplace surfaces. Builds on top of user-authored profiles.
- **Per-feed parameter overrides** beyond the profile's declared schema. Currently rejected: parameters not declared by the profile have no schema, no validation, no test path.
- **Bounded LLM agents (multi-turn tool loops).** Possible later as a different stage shape; would introduce client-side tool-loop orchestration, mid-run cost control, and prompt-injection handling. Not justified by the v1 use cases.
- **Additional LLM providers** beyond Anthropic. The `LlmCredential.provider` column is the seam.

## Open questions (deferred to per-phase sub-specs)

- Form of the registry — Ruby constant vs. small DSL vs. YAML files in `config/profiles/`. Decide in phase 1.
- Exact JSON Schema dialect for `parameter_schema` (Draft 7 vs. 2020-12). Decide in phase 1.
- Whether `Feed.url` migrates into `params.url` or stays a top-level column. Decide in phase 1.
- Encryption strategy for `LlmCredential.encrypted_key`. Likely Rails' built-in `encrypts`. Confirm in phase 2.
- Whether the processor for an LLM-loader profile is a single passthrough class or class-per-profile. Decide in phase 5.
