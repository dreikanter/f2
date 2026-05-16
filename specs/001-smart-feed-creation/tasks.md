---
description: "Tasks: Smart Feed Creation"
---

# Tasks: Smart Feed Creation

**Input**: Design documents from [`/specs/001-smart-feed-creation/`](./)

**Prerequisites**: [`plan.md`](./plan.md), [`spec.md`](./spec.md), [`research.md`](./research.md), [`data-model.md`](./data-model.md), [`contracts/`](./contracts/), [`quickstart.md`](./quickstart.md), [`notes/profile-contracts.md`](./notes/profile-contracts.md)

**Tests**: Tests are **mandatory** in this project per the constitution (principle II — *Tests Travel With Code, NON-NEGOTIABLE*). Each implementation task includes its tests in the same commit; tests are not split into separate tasks unless they exist purely as integration/system tests across multiple components. **Dependency-only commits** (gem additions in T001/T002 and equivalent config-only changes) are exempt from per-commit test inclusion because they introduce no runtime behavior to assert; the consuming task's tests cover any new behavior the dependency enables.

**Organization**: Tasks are grouped by user story per spec.md priorities (P1 → P2 → P3). Each user story phase produces a complete, independently shippable increment.

**Atomic commits** (constitution principle III): each task = one meaningful commit. The task description names the file paths touched. Each task ends with `bin/rails test` and `bin/rubocop -f github` green before commit.

## Format: `[TaskID] [P?] [Story?] Description with file paths`

- **[P]**: parallelizable (different files, no incomplete-task dependencies)
- **[Story]**: `[US1]`, `[US2]`, `[US3]` for user-story-phase tasks; absent for Setup / Foundational / Polish

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Add new gems and shared scaffolding all subsequent phases depend on.

- [ ] T001 Add `ruby_llm` gem to `Gemfile` and run `bundle install`; commit `Gemfile` + `Gemfile.lock`. (No test — dependency-only commit.)
- [X] T002 Add `json_schemer` gem to `Gemfile` and run `bundle install`; commit `Gemfile` + `Gemfile.lock`. (No test.)
- [ ] T003 [P] Create `config/llm_rates.yml` with per-model token cost table (Anthropic models initially); add `app/services/llm_client/rate_table.rb` loader with test in `test/services/llm_client/rate_table_test.rb`.
- [X] T004 [P] Add `test/support/feed_profile_validator.rb` (test helper) that validates the enriched `FeedProfile::PROFILES` shape using `json_schemer`; add `test/models/feed_profile_validator_test.rb` covering valid + malformed entries. (Registry is a frozen constant — covered in CI, no runtime boot hook needed.)

**Checkpoint**: Project boots cleanly with new gems; `FeedProfile::PROFILES` shape is validated in CI.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Schema changes, profile-registry refactor, detection contract change, preview pipeline scaffold. **All user stories depend on these.**

- [X] T005 Add migration `db/migrate/*_drop_url_add_params_to_feeds.rb` — drops `feeds.url` column, adds `feeds.params jsonb NOT NULL DEFAULT '{}'`. Reversibility verified on an empty DB (per A6, no production data). Test: `test/models/feed_test.rb` updated for `params`.
- [X] T006 Add migration `db/migrate/*_add_candidates_to_feed_details.rb` — `feed_details.candidates jsonb NOT NULL DEFAULT '[]'`. Reversibility verified. Test: `test/models/feed_detail_test.rb` updated.
- [X] T007 Refactor `app/models/feed_profile.rb` to the enriched per-entry shape per [`contracts/profile_registry.md`](./contracts/profile_registry.md) (`input_shape`, `parameter_schema`, `loader/processor/normalizer { class:, config: }`, `matcher`); migrate `rss` and `xkcd` entries to the new shape; update `test/models/feed_profile_test.rb` covering registry validation, lookup helpers (`matchers_for`, `depends_on_ai?`, `parameter_schema_for`).
- [X] T008 [P] Add `Feed#url` accessor in `app/models/feed.rb` returning `params["url"]`; add `params` schema validation against `FeedProfile[feed_profile_key].parameter_schema`; update `test/models/feed_test.rb` for both behaviors.
- [ ] T009 [P] Create `app/services/input_classifier.rb` returning `:url | :handle | :query | :malformed` per research §10. Tests in `test/services/input_classifier_test.rb` covering each shape including edge cases (whitespace-only, single char, IDN URLs, fediverse `@user@instance` handles).
- [ ] T010 Refactor `app/services/profile_matcher/base.rb` to declare `input_shape` and `match_specificity` (class-level DSL); update `test/services/profile_matcher/base_test.rb`.
- [ ] T011 [P] Update `app/services/profile_matcher/rss_profile_matcher.rb` to declare `input_shape: :url`, `match_specificity: 10`; update `test/services/profile_matcher/rss_profile_matcher_test.rb`.
- [ ] T012 [P] Update `app/services/profile_matcher/xkcd_profile_matcher.rb` to declare `input_shape: :url`, `match_specificity: 100` (outranks RSS); update `test/services/profile_matcher/xkcd_profile_matcher_test.rb`.
- [ ] T013 Refactor `app/services/feed_profile_detector.rb` to return a `DetectionResult` (`Data.define`) with ranked `DetectionCandidate` array per [`contracts/detection.md`](./contracts/detection.md). Implements ranking algorithm (non-AI before AI; specificity DESC; registration order tiebreaker). Sets `Thread.current[:llm_detection_phase] = true` for the duration. Tests in `test/services/feed_profile_detector_test.rb` cover: zero matches, one match, multi-match ordering, AI-after-non-AI rule, specificity wins, exception in one matcher doesn't abort chain, deterministic order on re-runs.
- [ ] T014 Update `app/services/feed_details_fetcher.rb` to call new detector contract; persist `feed_details.candidates` and mirror recommended into existing `feed_profile_key`/`title` columns; tests in `test/services/feed_details_fetcher_test.rb`.
- [ ] T015 Update `app/jobs/feed_details_job.rb` (signature unchanged, behavior follows fetcher) and `app/controllers/feed_details_controller.rb` to surface `candidates` in the Turbo Stream payload via the existing `_form_expanded` swap; controller tests in `test/controllers/feed_details_controller_test.rb` cover single-candidate, multi-candidate, and AI-fallback-only payloads.
- [ ] T016 [P] Add `Normalizer::Base#validate_universal_post_shape!` helper asserting all required Post fields present per [`notes/profile-contracts.md`](./notes/profile-contracts.md) §1; update `app/services/normalizer/base.rb` to invoke it in `normalize`; tests in `test/services/normalizer/base_test.rb`.
- [ ] T017 [P] Add `app/services/preview_token.rb` (HMAC sign + verify of `(user_id, profile_key, params_digest, generated_at)` with 60-min expiry) per [`contracts/preview.md`](./contracts/preview.md); tests in `test/services/preview_token_test.rb`.
- [ ] T018 Add `enabling_requires_recent_preview` validation to `app/models/feed.rb`: when `state` transitions `disabled → enabled`, `Current.preview_token` (or an attr) MUST verify against current `(profile_key, params)`. Tests in `test/models/feed_test.rb`.
- [ ] T019 Create `app/services/feed_preview_service.rb` per [`contracts/preview.md`](./contracts/preview.md) with `Preview` and `PostDraft` `Data.define` classes; reuses `FeedRefreshWorkflow` with `preview: true` mode (add `preview:` kwarg to `app/services/feed_refresh_workflow.rb`); supports cache key, refresh bypass, limit clamping (2..5). Tests in `test/services/feed_preview_service_test.rb` cover non-AI success, empty source, source unreachable, cache hit, cache miss, refresh bypass, limit clamping, preview_token issuance.
- [ ] T020 Create `app/jobs/feed_preview_job.rb` wrapping `FeedPreviewService.call` for async path; writes preview to `Rails.cache`; broadcasts Turbo Stream to refresh `<turbo-frame id="feed-preview">`. Tests in `test/jobs/feed_preview_job_test.rb` cover success → cache populated, failure → cache populated with failure marker.

**Checkpoint**: Detection returns ranked candidates; preview pipeline is callable for non-AI profiles; FR-016 state-gating in place. Story 1 implementation can begin.

---

## Phase 3: User Story 1 — RSS feed via URL paste (Priority: P1) 🎯 MVP

**Goal**: Pasting an RSS URL produces a confirmed, enabled feed with a preview-rendered confirmation step. Story 1 alone gives users a working feed-creation flow.

**Independent Test**: Paste the URL of a known-good RSS source. The system creates the feed without asking the user to choose a "source type" or fill any fields beyond name, group, and schedule, and the preview shows recent posts that match expectations. (See `quickstart.md` §1.)

- [ ] T021 [P] [US1] Create `app/javascript/controllers/candidate_chooser_controller.js` (Stimulus): emits `feed:candidate-changed` event on radio change. Lightweight unit-style test in `test/system/components/candidate_chooser_test.rb` exercising the radio→event behavior in a system test (Capybara + headless Chrome).
- [ ] T022 [P] [US1] Create `app/javascript/controllers/preview_controller.js` (Stimulus): "Refresh preview" button → POSTs to preview controller; listens for `feed:candidate-changed` to reload the preview frame. System test in `test/system/components/preview_refresh_test.rb`.
- [ ] T023 [P] [US1] Update `app/views/feeds/_form_collapsed.html.erb`: broaden placeholder text per FR-022 (no "URL" jargon); use `data-key="form.entry-input"` selector. Update `test/controllers/feeds_controller_test.rb#test_new_renders_collapsed_form_with_neutral_placeholder`.
- [ ] T024 [P] [US1] Create `app/views/feeds/_candidate_chooser.html.erb` rendering recommended + alternatives per [`contracts/http_routes.md`](./contracts/http_routes.md); each option labeled with `data-key="candidate.<profile_key>"`; AI badge with `data-key="candidate.ai-badge"`. Tests in `test/views/feeds/_candidate_chooser_test.rb`.
- [ ] T025 [P] [US1] Create `app/views/feeds/_preview.html.erb` rendering 2–5 `PostDraft` cards (DaisyUI card layout): body, supplementary comments (collapsed), image thumbnails, source URL link. `data-key="preview.post.<n>"` per card. Tests in `test/views/feeds/_preview_test.rb`.
- [ ] T026 [P] [US1] Create `app/views/feeds/_preview_loading.html.erb` with progress hint and polling target. Tests in `test/views/feeds/_preview_loading_test.rb`.
- [ ] T027 [P] [US1] Create `app/views/feeds/_preview_failed.html.erb` with friendly error message, "Try again" button (POST `/feeds/:id/preview`), and "Save as disabled" button (per FR-017). `data-key="preview.failed"`. Tests in `test/views/feeds/_preview_failed_test.rb`.
- [ ] T028 [US1] Update `app/views/feeds/_form_expanded.html.erb`: render `_candidate_chooser` when `candidates.length > 1`; embed `<turbo-frame id="feed-preview" src="<feed_preview_path...>">` for lazy preview load; render parameter form fields generated from `FeedProfile.parameter_schema_for(key)`. `data-key` attributes throughout. Tests in `test/views/feeds/_form_expanded_test.rb` cover single-candidate and multi-candidate variants.
- [ ] T029 [US1] Add `resource :preview, only: %i[show create destroy]` nested under `resources :feeds` in `config/routes.rb`; create `app/controllers/feed_previews_controller.rb` with `#show` (return cached or enqueue job + loading partial), `#create` (refresh: bust cache + enqueue), `#destroy` (clear preview state). Handle `feed_id = "draft"` sentinel for new-feed previews keyed on `feed_detail_id`. Tests in `test/controllers/feed_previews_controller_test.rb` cover cache-hit, cache-miss-async, refresh, draft-feed flow.
- [ ] T030 [US1] Update `app/controllers/feeds_controller.rb#create`: extract `preview_token` from params; verify against `(profile_key, params)`; if valid → save with `state: :enabled`; if invalid/absent → save with `state: :disabled` (the model's `enabling_requires_recent_preview` enforces). Save-as-disabled label in form drives `enable_feed: 0`. Tests in `test/controllers/feeds_controller_test.rb` cover preview-token-present-create-enabled, preview-token-absent-create-disabled, save-anyway-create-disabled.
- [ ] T031 [US1] Update `app/controllers/feeds_controller.rb#update` to branch operational vs source-side edits per FR-026/FR-027/FR-028: detect changed source-side fields; re-trigger detection + preview (re-apply preview_token requirement); warn on profile switch. Tests in `test/controllers/feeds_controller_test.rb` cover operational-only edit (no preview re-run), source-edit (preview re-run, state may flip), profile-switch warning.
- [ ] T032 [US1] Add cancel-during-detection affordance per FR-004: extend `resource :feed_details` in `config/routes.rb` to include `:destroy`; add `FeedDetailsController#destroy` that removes the user's in-progress `FeedDetail` and returns a Turbo Stream replacing `#feed-form` with `_form_collapsed` prefilled from the destroyed record's input; add a "Cancel" button (`data-key="loading.cancel"`) to `app/views/feeds/_identification_loading.html.erb` and `app/views/feeds/_preview_loading.html.erb` that submits the DELETE. Tests in `test/controllers/feed_details_controller_test.rb#test_destroy_returns_user_to_collapsed_form_with_input` and `test/system/components/cancel_during_loading_test.rb`.
- [ ] T033 [US1] Add `test/system/smart_feed_creation_rss_test.rb` covering Story 1 happy path (RSS URL paste → polling → expanded form with candidate chooser hidden → preview renders → save → enabled feed exists in DB) and XKCD specificity check (XKCD outranks RSS).

**Checkpoint**: Story 1 ships. RSS feed creation works end-to-end with the new contract and preview gating. MVP is shippable.

---

## Phase 4: User Story 2 — AI extraction for sites without RSS (Priority: P2)

**Goal**: Pasting a URL with no RSS gracefully offers AI extraction, gates on AI credentials, and ships a working feed. The bulk of the LLM machinery lands here and is reused by Story 3.

**Independent Test**: Paste a URL of a site with no RSS. The system offers AI extraction; accepting without credentials triggers a guided credential-setup flow; accepting with credentials creates a working feed with a preview. (See `quickstart.md` §2.)

### Migrations and models (parallel)

- [ ] T034 [P] [US2] Create migration `db/migrate/*_create_llm_credentials.rb` per data-model §1: columns, partial unique index `(user_id, provider) WHERE is_default = TRUE`, indexes on `(user_id, state)`. Reversibility verified.
- [ ] T035 [P] [US2] Create migration `db/migrate/*_create_llm_usages.rb` per data-model §2: columns, indexes `(user_id, started_at)`, `(feed_id, started_at)`, `(profile_key, started_at)`, `(purpose, started_at)`. Reversibility verified.
- [ ] T036 [P] [US2] Create migration `db/migrate/*_add_llm_credential_id_to_feeds.rb`: nullable FK + index. Reversibility verified.
- [ ] T037 [US2] Create `app/models/llm_credential.rb` with `encrypts :credential_data`, validations (provider in registry, `display_name` uniqueness scoped to `(user_id, provider)`, `credential_data` validated against `LlmProvider::PROVIDERS[provider][:credential_schema]`), `is_default` callback un-defaulting siblings, `state` enum mirroring `AccessToken`. Factory in `test/factories/llm_credentials.rb`. Tests in `test/models/llm_credential_test.rb` cover validations, default uniqueness (including a partial-unique-index race test), encryption round-trip, schema validation per provider, destroy → nullify dependent feeds → disable feeds without other usable credentials.
- [ ] T038 [US2] Create `app/models/llm_usage.rb` with associations and enums (`stage`, `purpose`, `outcome`). Factory in `test/factories/llm_usages.rb`. Tests in `test/models/llm_usage_test.rb` cover field validations and enum behavior.
- [ ] T039 [US2] Create `app/models/llm_provider.rb` (code-only registry per data-model §8) with Anthropic entry: display_name, ruby_llm_provider symbol, credential_schema (JSON Schema for `{api_key}`), `validate_call` lambda. Tests in `test/models/llm_provider_test.rb`.

### LlmClient and adapter

- [ ] T040 [US2] Create `app/services/llm_client/adapter.rb` wrapping the `ruby_llm` gem per [`contracts/llm_client.md`](./contracts/llm_client.md): one class, multi-provider via the `provider:` argument; delegates structured-output dispatch to RubyLLM; surfaces token usage (including `cache_read_tokens` for Anthropic prompt caching). Tests in `test/services/llm_client/adapter_test.rb` use `WebMock` with fixture responses for each registered provider: success, schema-violation (raises `SchemaError`), 429 (raises `RateLimited` with `retry_after`), 5xx (raises `ProviderError`), timeout (raises `Timeout`). Anthropic-specific assertions cover prompt-cache token surfacing and server-side `web_search` / `web_fetch` tool pass-through.
- [ ] T041 [US2] Create `app/services/llm_client.rb` (top-level) per [`contracts/llm_client.md`](./contracts/llm_client.md): `for(feed)` / `for(user, provider)` / `for(credential)` factories; `call(...)` method that resolves credential → adapter → schema-validates response → writes `LlmUsage` row → returns `Result`. Detection guard (`raise DetectionForbidden if Thread.current[:llm_detection_phase]`). Reports unexpected errors via `Rails.error.report`. Tests in `test/services/llm_client_test.rb` use `Minitest::Mock` for the adapter; cover usage-row-on-success, usage-row-on-each-failure, schema validation, detection-guard fires, cost computation from rate table.

### Credentials UI and validation job

- [ ] T042 [US2] Create `app/jobs/llm_credential_validation_job.rb` calling `LlmClient.for(credential).call(...)` (using the adapter's `health_check`); writes `last_validated_at` / `last_error` / state. Tests in `test/jobs/llm_credential_validation_job_test.rb` cover happy path and provider-error path.
- [ ] T043 [US2] Add `resources :llm_credentials, except: %i[edit update]` in `config/routes.rb` with nested `resource :validation, only: %i[show]` and `resource :default, only: %i[update]`. Routing tests in `test/routes/llm_credentials_routes_test.rb`.
- [ ] T044 [US2] Create `app/controllers/llm_credentials_controller.rb` with `#index`, `#new`, `#show` (polling shell mirroring `AccessTokensController#show`), `#create` (enqueues validation job), `#destroy` (cascades per T037). Tests in `test/controllers/llm_credentials_controller_test.rb`.
- [ ] T045 [US2] Create `app/controllers/llm_credentials/defaults_controller.rb` for `#update` ("Make default"): wraps the un-default-others + set-default in a single transaction, relies on the partial unique index. Returns Turbo Stream updating both rows' "Default" badges. Tests in `test/controllers/llm_credentials/defaults_controller_test.rb` cover set-default-when-none-exists, switch-default-from-another, attempt-to-double-default (DB rejects).
- [ ] T046 [US2] Create `app/views/llm_credentials/index.html.erb`, `new.html.erb`, `show.html.erb`, `_show_content.html.erb` per [`contracts/http_routes.md`](./contracts/http_routes.md): provider picker → form fields generated dynamically from `LlmProvider::PROVIDERS[provider][:credential_schema]`. `data-key` attributes throughout. View tests in `test/views/llm_credentials/`. Vocabulary firewall enforced — no banned words.

### LLM-using stages and first AI profile

- [ ] T047 [P] [US2] Create `app/services/loader/llm_loader.rb` consuming `LlmClient`; reads `*_config` from profile (model, prompt_template, output_schema, tools); supports `limit:` kwarg for preview mode. Tests in `test/services/loader/llm_loader_test.rb` stub `LlmClient`.
- [ ] T048 [P] [US2] Create `app/services/processor/passthrough_processor.rb` mapping loader-emitted structured items to `FeedEntry` instances (uid from item's `uid` field). Tests in `test/services/processor/passthrough_processor_test.rb`.
- [ ] T049 [P] [US2] Create `app/services/normalizer/llm_normalizer.rb` consuming `LlmClient` (for profiles where the normalizer is the AI step, e.g., LLM rewrite). Tests in `test/services/normalizer/llm_normalizer_test.rb` stub `LlmClient`.
- [ ] T050 [P] [US2] Create `app/services/profile_matcher/llm_website_extractor_matcher.rb`: `input_shape: :url`, `match_specificity: 1` (lowest), `depends_on_ai: true`, matches any URL where no non-AI matcher fired. Tests in `test/services/profile_matcher/llm_website_extractor_matcher_test.rb`.
- [ ] T051 [US2] Add `llm_website_extractor` profile entry to `app/models/feed_profile.rb`: prompt template, `output_schema` (universal post fields per notes/profile-contracts.md §1, plus permalink extraction per research §9), tools `["web_search", "web_fetch"]`, uid strategy (SHA-256 of canonicalized permalink, deterministic fallback). Tests in `test/models/feed_profile_test.rb` (profile-level integration test exercising parameter_schema validation).
- [ ] T052 [US2] Update `app/services/feed_preview_service.rb` to handle AI-backed profiles: resolve `LlmCredential`; map `LlmClient` failure modes to `FeedPreviewService::AiUnparseable / ProviderError / CredentialMissing` per [`contracts/preview.md`](./contracts/preview.md). Tests in `test/services/feed_preview_service_test.rb` extend coverage to AI paths.

### Feed creation UI updates for AI gate

- [ ] T053 [US2] Update `app/controllers/feeds_controller.rb` and `feed_previews_controller.rb` to handle credential gate per FR-010/FR-011: when chosen profile `depends_on_ai` and user has no acceptable credential → render inline `_credential_gate` partial preserving in-progress feed input. Tests in `test/controllers/feeds_controller_test.rb`.
- [ ] T054 [US2] Update `app/views/feeds/_form_expanded.html.erb` and add `app/views/feeds/_credential_gate.html.erb`: render multi-credential picker preselecting user's default per FR-013; hide picker when only one acceptable credential. `data-key="credentials.picker"`, `data-key="credentials.gate"`. Tests in `test/views/feeds/`.
- [ ] T055 [US2] Add cost message in `app/views/feeds/_form_expanded.html.erb` when an AI candidate is selected per FR-023: "AI fetches (including the preview) cost tokens — see your spend on the feed page." Shown once, dismissible. Vocabulary verified by test in `test/views/feeds/_form_expanded_test.rb`.
- [ ] T056 [US2] Add `test/system/smart_feed_creation_ai_website_test.rb` covering Story 2 paths: with credentials present (paste no-RSS URL → AI offer → preview → save → enabled), without credentials (paste → AI offer → guided credential setup → return → preview → save), preview failure save-anyway (preview fails → "Save as disabled" → feed exists in `disabled` state).

**Checkpoint**: Story 2 ships. AI extraction for URL sources works end-to-end. Credentials UX is in place. Preview pipeline now exercises both non-AI and AI paths.

---

## Phase 5: User Story 3 — Handle / search query inputs (Priority: P3)

**Goal**: Non-URL inputs (handles, free-text queries) route through AI-backed profiles. Reuses all Story 2 LLM machinery.

**Independent Test**: Type a handle or free-text query (not a URL) into the entry box. The system offers sensible AI-backed follow options and confirming creates a working feed. (See `quickstart.md` §3.)

- [ ] T057 [P] [US3] Create `app/services/profile_matcher/llm_handle_search_matcher.rb`: `input_shape: :handle`, `match_specificity: 50`, `depends_on_ai: true`. Tests in `test/services/profile_matcher/llm_handle_search_matcher_test.rb`.
- [ ] T058 [P] [US3] Create `app/services/profile_matcher/llm_web_search_matcher.rb`: `input_shape: :query`, `match_specificity: 50`, `depends_on_ai: true`. Tests in `test/services/profile_matcher/llm_web_search_matcher_test.rb`.
- [ ] T059 [US3] Add `llm_handle_search` profile entry to `app/models/feed_profile.rb`: prompt template referencing the handle parameter, `output_schema`, `tools: ["web_search"]`. Tests in `test/models/feed_profile_test.rb`.
- [ ] T060 [US3] Add `llm_web_search` profile entry to `app/models/feed_profile.rb`: prompt template referencing the query parameter, `output_schema`, `tools: ["web_search"]`. Tests in `test/models/feed_profile_test.rb`.
- [ ] T061 [US3] Update `app/views/feeds/_candidate_chooser.html.erb` to render plain-language candidate descriptions for non-URL inputs ("Follow `@username` on X via AI search", "Follow web search results for `<query>`") via a `feeds_helper.rb` helper. Tests in `test/helpers/feeds_helper_test.rb` and `test/views/feeds/_candidate_chooser_test.rb`.
- [ ] T062 [US3] Add `test/system/smart_feed_creation_handle_query_test.rb` covering Story 3 paths: handle input → AI handle-search offer → save; free-text query → AI web-search offer → save.

**Checkpoint**: Story 3 ships. Full feature live across all input shapes.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: System-level integration tests, vocabulary enforcement, lint pass.

- [ ] T063 [P] Add `test/system/smart_feed_creation_vocabulary_test.rb` verifying FR-022 + SC-005: scrape rendered HTML for `/feeds/new` (each detection state), `/llm_credentials`, `/llm_credentials/new`, `/llm_credentials/:id` and assert none of the banned implementation words ("profile", "matcher", "pipeline", "stage", "loader", "processor", "normalizer", "LLM") appear in any user-visible string. Allows "AI", "AI credentials", and provider brand names.
- [ ] T064 [P] Add `test/system/smart_feed_creation_state_gating_test.rb` verifying FR-016/FR-017: feed save-with-valid-preview-token → `enabled`; feed save-without-token → `disabled`; tampered preview-token rejected; expired preview-token rejected.
- [ ] T065 [P] Add `test/system/smart_feed_creation_reload_test.rb` verifying FR-018/FR-019: reload of in-progress confirmation does not re-run detection (assert no new `FeedDetailsJob` run); does not re-run preview (assert `LlmUsage` count unchanged for AI feeds, no new `FeedPreviewJob` run); "Refresh preview" click triggers new `LlmUsage` row.
- [ ] T066 [P] Add `test/system/smart_feed_creation_edit_test.rb` verifying FR-026/FR-027/FR-028: operational-field edit doesn't run preview; source-field edit re-runs detection + preview and re-gates `enabled`; profile-switch warning fires + requires confirmation.
- [ ] T067 [P] Run `bin/rubocop -f github` over all new/modified files; fix any violations.
- [ ] T068 Final pass: review `quickstart.md` end-to-end against the implemented feature; correct any drift; ensure `data-key` selectors used in system tests match the partials.

---

## Dependencies & Execution Order

### Phase dependencies

- **Setup (T001–T004)** — no deps; can start immediately.
- **Foundational (T005–T020)** — depends on Setup; **blocks all stories**.
- **User Story 1 (T021–T033)** — depends on Foundational. MVP-shippable on its own.
- **User Story 2 (T034–T056)** — depends on Foundational. Independent of Story 1 (different files), so a separate developer can work in parallel on Story 2 once Foundational is done.
- **User Story 3 (T057–T062)** — depends on Story 2 (reuses `LlmClient`, `Loader::LlmLoader`, `Normalizer::LlmNormalizer`, `Processor::PassthroughProcessor`, credentials UI). Cannot start until T041, T047, T048, T049, T051 are complete.
- **Polish (T063–T068)** — depends on the user stories the test asserts against (T063–T066 each depend on the corresponding story). T067–T068 are the final gate.

### Within Foundational (T005–T020)

- T005, T006 (migrations) → block T007, T008, T013–T015.
- T007 (registry refactor) → blocks T013.
- T009 (input classifier) → blocks T013.
- T010 (matcher base) → blocks T011, T012, T013.
- T013 (detector contract) → blocks T014, T015.
- T016 (normalizer base helper) → blocks downstream normalizers (no story-1 normalizer changes; affects Story 2/3 normalizers).
- T017 (preview_token util) → blocks T018, T019, T030.
- T018 (Feed validation) → blocks T030.
- T019 (FeedPreviewService) → blocks T020, T029, T052.

### Within Story 1 (T021–T033)

- T021–T027 are mostly parallel ([P] view + Stimulus partials).
- T028 depends on T024–T027 (assembles partials).
- T029 depends on T019 (FeedPreviewService) and T020 (FeedPreviewJob).
- T030 depends on T017, T018, T029.
- T031 depends on T030 (extends `update`).
- T032 (cancel affordance) depends on T015 (FeedDetailsController) and T026 (preview loading partial).
- T033 depends on T021–T032 (full system test).

### Within Story 2 (T034–T056)

- T034–T036 (migrations) parallel; block T037, T038.
- T039 (provider registry) parallel.
- T040 (RubyLLM adapter) parallel.
- T041 (LlmClient) depends on T039, T040.
- T042 (validation job) depends on T041, T037.
- T043–T046 (credentials controller/views/routes) depend on T037, T038; T045 depends on T037.
- T047–T049 (LLM stages) parallel after T041.
- T050 (matcher) parallel.
- T051 (profile entry) depends on T047, T048, T049, T050.
- T052 (FeedPreviewService AI updates) depends on T041.
- T053 (controller credential gate) depends on T037, T043.
- T054 (picker view) depends on T037.
- T055 (cost message) parallel after T028.
- T056 (system test) depends on all above.

### Within Story 3 (T057–T062)

- T057, T058 (matchers) parallel.
- T059, T060 (profiles) depend on T047, T048, T049 (existing LLM stages).
- T061 (chooser descriptions) parallel.
- T062 (system test) depends on all above.

### Parallel opportunities summary

- After Setup completes: T005, T006 in parallel (different migrations); then T009, T010, T011, T012, T016, T017 in parallel.
- After Foundational completes: Story 1 and Story 2 can be developed in parallel by separate developers.
- Within Story 1: T021–T027 in parallel.
- Within Story 2: T034–T036 in parallel; T039, T040 in parallel; T047–T049 in parallel; T050 in parallel.
- Within Story 3: T057, T058 in parallel.
- Within Polish: T063–T066 in parallel; T067 in parallel; T068 last.

---

## Suggested MVP Scope

**Stop at Checkpoint after T033** for the smallest viable shipping increment: pasting an RSS URL produces a confirmed, enabled feed with a preview-rendered confirmation step. All non-RSS UX (AI extraction, handles, queries) is out of MVP scope but the foundation it sits on is in place.

**Increment 2 (after T056)**: Story 2 lights up the AI on-ramp. Most users will see this as the headline release.

**Increment 3 (after T062)**: Story 3 finishes the input domain. Full feature.

---

## Notes

- Every implementation task ends with `bin/rails test` and `bin/rubocop -f github` green before commit (constitution principle II + III).
- Each task = one commit (constitution principle III). Subject ≤ 50 chars, imperative.
- Migrations are committed with their model changes and tests in the same commit.
- View partials are committed with their tests and any associated Stimulus controller in the same commit.
- The **vocabulary firewall** test (T063) is intentionally cross-cutting; new view tasks (T023–T028, T046, T054, T055) include local vocabulary checks, but T063 is the catch-all backstop.
- `data-key` attributes are used for all new test-targeted DOM elements (project convention from CLAUDE.md).
- AI calls in tests are stubbed at the `LlmClient` seam; the adapter is tested in isolation with `WebMock`. No live AI calls in CI.
