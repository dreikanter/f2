# Implementation Plan: Smart Feed Creation

**Date**: 2026-05-16 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `/specs/001-smart-feed-creation/spec.md`

**Companion docs**: [`research.md`](./research.md), [`data-model.md`](./data-model.md), [`contracts/`](./contracts/), [`quickstart.md`](./quickstart.md), [`notes/profile-contracts.md`](./notes/profile-contracts.md)

## Summary

Replace the current "paste URL, single matcher chain, single profile result" flow with a generalized "paste anything, ranked profile list, inline confirmation with live preview" flow that gracefully extends to AI-backed sources. The pipeline shape (Loader → Processor → Normalizer) does not change; the changes concentrate at three seams:

1. **Profile registry** gains structure (`input_shape`, `parameter_schema`, per-stage `*_config`) so AI-using stages slot in alongside RSS without UI changes.
2. **Detection** returns a *ranked list* of matching profiles instead of a single profile or an error, with deterministic ranking rules (specific > generic; non-AI > AI for the same input). Detection never spends AI tokens.
3. **Confirmation** acquires a **preview pane** (2–5 sample posts rendered structurally) that gates the `enabled` state — saving with a green preview activates the feed; saving without one keeps it `disabled`.

Two new resources accompany the work: `LlmCredential` (per-user, per-provider, with a `default` flag, mirroring the `AccessToken` lifecycle) and `LlmUsage` (per-call attribution for cost transparency). A new `LlmClient` service is the only entry point for AI calls; stage classes and the preview service consume it as a service, never the provider SDK directly.

The work spans parent-spec phases 1, 2, 3, and 5, but is sliced here so Story 1 (RSS happy path with preview) ships independently of Story 2 (AI extraction with credentials gate) and Story 3 (handles / search queries).

## Technical Context

**Language/Version**: Ruby (pinned in `.ruby-version`, managed by mise)

**Primary Dependencies**: Rails edge, Turbo, Stimulus, Tailwind CSS + DaisyUI, SolidQueue, Feedjira (RSS parsing, existing), Nokogiri (existing), `httpx`/internal `HttpClient` (existing). New: `ruby_llm` gem (multi-provider LLM SDK; Anthropic first, OpenAI / others follow as registry entries); `json_schemer` for parameter and LLM-output validation.

**Storage**: PostgreSQL via Rails migrations. New tables: `llm_credentials`, `llm_usages`. Modified tables: `feed_details` (carry ranked-profile list), `feeds` (add `params` JSONB; per A6, no production data, free to drop `feeds.url` once profile params absorb it). Existing `feed_profile.rb` registry remains code-defined (parent-spec future-scope move to DB is deferred).

**Testing**: Minitest (`bin/rails test`) with FactoryBot. AI calls stubbed via test doubles at the `LlmClient` seam (no provider SDK in tests; no VCR — see `research.md` §5). Migrations verified reversible per constitution.

**Target Platform**: Web app served by Rails / Puma. SolidQueue for background jobs. Kamal deployment.

**Project Type**: Rails monolith. Single repository, no separate frontend/backend.

**Performance Goals**:
- Detection completes ≤ 30 s (existing limit, A10).
- Preview generation completes ≤ 30 s for non-AI profiles, ≤ 60 s for AI profiles (single LLM call, model-dependent).
- Median paste-to-confirmed-feed under 10 s for single-candidate inputs (SC-002).
- Auto-fill happy-path UI updates land via Turbo Streams within polling cadence (currently 2 s).

**Constraints**:
- 10 detection attempts per minute per user (rate limit, A10).
- Detection MUST NOT call any paid AI service (FR-007).
- AI calls MUST go through `LlmClient`; stages MUST NOT instantiate provider SDKs directly (parent spec).
- `LlmClient` MUST write one `LlmUsage` row per call regardless of outcome (parent spec).
- All `Rails.error.report` for handled exceptions (constitution principle V).

**Scale/Scope**: 31 functional requirements, 8 success criteria, 3 user stories. New LOC budget ≈ 1,500–3,000 (excluding generated migrations and tests). Single-tenant per user; no horizontal scaling concerns introduced.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Validated against [`.specify/memory/constitution.md`](../../.specify/memory/constitution.md) v1.0.0:

| Principle | Compliance | Notes |
|-----------|------------|-------|
| **I. Rails Conventions First** | ✅ | New work uses resourceful routes (`resources :llm_credentials`, `resource :feed_preview`); no `member`/`collection` routes; no blank action methods; trailing newlines on all source files. |
| **II. Tests Travel With Code (NON-NEGOTIABLE)** | ✅ | Every new model, service, controller, view, and migration ships with a test in the same commit. `bin/rails test` and `bin/rubocop -f github` green before each commit. Migrations verified reversible. FactoryBot factories for new models. Lazy memoized helpers in tests. `data-key` attributes for new view selectors. |
| **III. Atomic, Reviewable Commits** | ✅ | `tasks.md` will sequence work as small, complete commits — one model + factory + migration + test per commit; one stage class + test per commit; one controller action + view + test per commit. PR descriptions use `.github/pull_request_template.md`. |
| **IV. Approachable UI Voice** | ✅ | FR-022 enforces this directly. Vocabulary firewall ("profile / matcher / pipeline / stage / loader / processor / normalizer / LLM" banned in user copy). UI strings drafted and reviewed against the constitution's banned-words list as part of each view PR. |
| **V. Observable Error Handling** | ✅ | All AI calls inside `LlmClient` use `Rails.error.handle` for known provider/schema failures; unexpected failures use `Rails.error.report` with `feed_id`, `profile_key`, `provider`, `stage` context. Detection failures, preview failures, and credential validation failures all report through `Rails.error`. No silent rescues. |

**No violations**. Complexity Tracking section below is empty.

Re-check post-Phase-1: see end of [`data-model.md`](./data-model.md). No new violations introduced by the design.

## Project Structure

### Documentation (this feature)

```text
specs/001-smart-feed-creation/
├── spec.md                          # Feature spec (/speckit-specify, /speckit-clarify)
├── plan.md                          # This file
├── research.md                      # Phase 0 output — design forks resolved
├── data-model.md                    # Phase 1 output — entities, fields, transitions
├── contracts/                       # Phase 1 output — service / job / route contracts
│   ├── profile_registry.md          # Enriched FeedProfile entry shape
│   ├── detection.md                 # Detection input/output contract
│   ├── llm_client.md                # LlmClient interface
│   ├── preview.md                   # FeedPreviewService interface
│   └── http_routes.md               # New/modified Rails routes + Turbo Stream payloads
├── quickstart.md                    # Phase 1 output — developer verification walkthrough
├── notes/
│   └── profile-contracts.md         # Pre-existing implementation notes (post fields, dedup uid policy, AI output schema)
└── tasks.md                         # Phase 2 output (created by /speckit-tasks)
```

### Source Code (repository root)

Rails monolith. New files marked `(new)`; modified files marked `(mod)`. Test files mirror the source paths under `test/`.

```text
app/
├── models/
│   ├── feed.rb                              (mod) — add :params JSONB; gate :enabled state on preview success
│   ├── feed_detail.rb                       (mod) — carry ranked candidate list (JSONB column)
│   ├── feed_profile.rb                      (mod) — enriched registry: input_shape, parameter_schema, *_config slots
│   ├── llm_credential.rb                    (new) — provider, credential_data JSONB, default flag, validation state
│   └── llm_usage.rb                         (new) — per-call attribution
├── controllers/
│   ├── feed_details_controller.rb           (mod) — return ranked-list payload
│   ├── feeds_controller.rb                  (mod) — preview gating; edit semantics (operational vs source-side)
│   ├── feed_previews_controller.rb          (new) — render/refresh preview
│   └── llm_credentials_controller.rb        (new) — list/add/validate/revoke; "Make default" affordance
├── jobs/
│   ├── feed_details_job.rb                  (mod) — produce ranked list
│   ├── feed_preview_job.rb                  (new) — async preview generation; writes LlmUsage if AI-backed
│   └── llm_credential_validation_job.rb     (new) — validates credential against provider on save
├── services/
│   ├── input_classifier.rb                  (new) — url | handle | query | malformed
│   ├── feed_profile_detector.rb             (mod) — return ranked array, not first hit
│   ├── feed_details_fetcher.rb              (mod) — drive new detector contract
│   ├── feed_preview_service.rb              (new) — bounded loader→processor→normalizer; non-persistent
│   ├── llm_client.rb                        (new) — chokepoint for all AI calls; wraps ruby_llm; writes LlmUsage
│   ├── profile_matcher/
│   │   ├── base.rb                          (mod) — declare input_shape; rank() helper
│   │   ├── xkcd_profile_matcher.rb          (mod) — declare input_shape: :url
│   │   ├── rss_profile_matcher.rb           (mod) — declare input_shape: :url
│   │   ├── llm_website_extractor_matcher.rb (new) — input_shape: :url, depends_on_ai: true
│   │   ├── llm_handle_search_matcher.rb     (new) — input_shape: :handle, depends_on_ai: true
│   │   └── llm_web_search_matcher.rb        (new) — input_shape: :query, depends_on_ai: true
│   ├── loader/
│   │   └── llm_loader.rb                    (new) — generic LLM-backed loader (uses LlmClient)
│   ├── processor/
│   │   └── passthrough_processor.rb         (new) — maps loader-emitted structured items to FeedEntry
│   └── normalizer/
│       └── llm_normalizer.rb                (new) — generic LLM-backed normalizer (uses LlmClient)
├── views/
│   ├── feeds/
│   │   ├── _form_collapsed.html.erb         (mod) — placeholder broadens beyond URL
│   │   ├── _form_expanded.html.erb          (mod) — embed candidate chooser + preview pane
│   │   ├── _candidate_chooser.html.erb      (new) — recommended + alternatives list
│   │   ├── _preview.html.erb                (new) — 2–5 sample posts in publish-shape
│   │   ├── _preview_failed.html.erb         (new) — friendly error + retry + "Save as disabled"
│   │   └── _identification_error.html.erb   (mod) — replaced by curated AI fallbacks (FR-005)
│   └── llm_credentials/
│       ├── index.html.erb                   (new)
│       ├── new.html.erb                     (new)
│       ├── show.html.erb                    (new) — polling shell, like access_tokens/show
│       └── _show_content.html.erb           (new)
├── javascript/controllers/
│   ├── candidate_chooser_controller.js      (new) — switches selected option, expands inline form
│   └── preview_controller.js                (new) — explicit "Refresh preview" affordance (FR-019)
└── components/
    └── (none required for this feature)

config/
├── routes.rb                                (mod) — add resources :llm_credentials with nested validation; add resource :feed_preview under feeds

db/migrate/
├── *_create_llm_credentials.rb              (new)
├── *_create_llm_usages.rb                   (new)
├── *_add_params_to_feeds.rb                 (new)
├── *_add_candidates_to_feed_details.rb      (new)
└── *_add_credential_ref_to_feeds.rb         (new) — feeds.llm_credential_id (nullable, FK)

test/
├── models/                                  — llm_credential_test.rb, llm_usage_test.rb, feed_test.rb (mod), feed_detail_test.rb (mod)
├── controllers/                             — feed_details, feeds, feed_previews, llm_credentials
├── jobs/                                    — feed_details_job (mod), feed_preview_job, llm_credential_validation_job
├── services/                                — input_classifier, feed_profile_detector (mod), feed_preview_service, llm_client, profile_matcher/* (mod + new), loader/llm_loader, processor/passthrough_processor, normalizer/llm_normalizer
├── system/                                  — smart_feed_creation_test.rb (Story 1, Story 2 happy paths end-to-end)
└── factories/                               — llm_credential, llm_usage
```

**Structure Decision**: Standard Rails monolith layout (CLAUDE.md says "Follow standard Rails conventions"). All new work fits under existing `app/{models,controllers,services,views,jobs}` with new sub-namespaces (`Loader::LlmLoader`, `Normalizer::LlmNormalizer`) where they parallel existing namespaces. `LlmClient` is the only chokepoint for AI calls and lives at `app/services/llm_client.rb` with no sub-namespace. No new top-level directories needed.

## Complexity Tracking

> **No constitution violations to justify.** This section is intentionally empty.
