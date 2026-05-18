# PR Slicing Plan: Smart Feed Creation

**Status**: in-progress

This document slices the remaining `tasks.md` work into reviewable PRs.
It is a companion to [`plan.md`](./plan.md) and [`tasks.md`](./tasks.md),
not a substitute — task-level requirements and acceptance still live in
those documents.

## Already merged

| PR     | Title                                                  | Tasks      |
| ------ | ------------------------------------------------------ | ---------- |
| `#388` | Smart feed creation foundations                        | T002, T004–T008 |
| `#390` | Smart feed creation — detection slice                  | T009–T016  |
| `#391` | Smart feed creation, preview foundations               | T017–T020  |

After `#391`, detection returns ranked candidates and the preview
service / job / token / state-gate validation are in place but not yet
wired into the UI.

## Remaining PRs

### PR 4 — Story 1: Preview UI primitives and preview controller

**Tasks**: T021, T022, T023, T024, T025, T026, T027, T029.

The Stimulus controllers (`candidate-chooser`, `preview`), the four
view partials (`_candidate_chooser`, `_preview`, `_preview_loading`,
`_preview_failed`), the `_form_collapsed` placeholder rewording, and
the new `Feeds::PreviewsController` (nested `resource :preview`).
Partials render in isolation and the controller exercises the cache /
enqueue / refresh / destroy paths, but `_form_expanded` does not yet
embed them. No user-visible change in the feed-creation flow yet.

### PR 5 — Story 1: Feed creation flow + MVP system test

**Tasks**: T028, T030, T031, T032, T033.

Assemble the partials into `_form_expanded` (chooser + lazy
`<turbo-frame>` + schema-driven params), wire preview-token gating
into `FeedsController#create`, split operational vs source-side edits
in `#update`, add the cancel-during-detection affordance, and ship
`smart_feed_creation_rss_test.rb`. **MVP shippable at this checkpoint.**

### PR 6 — Story 2: LLM credentials backend

**Tasks**: T001, T003, T034, T035, T036, T037, T038, T039.

Add the `ruby_llm` gem, the per-model rate table at
`config/llm_rates.yml`, three migrations (`llm_credentials`,
`llm_usages`, `feeds.llm_credential_id`), the `LlmCredential` /
`LlmUsage` / `LlmProvider` models with factories, and the
encryption + default-uniqueness partial-index constraints.

### PR 7 — Story 2: `LlmClient` + credentials UI

**Tasks**: T041, T042, T043, T044, T045, T046.

The `LlmClient` chokepoint (WebMock-driven tests, detection guard,
one `LlmUsage` row per call), `LlmCredentialValidationJob`, routes,
`LlmCredentialsController`, the nested defaults controller, and the
`llm_credentials/*` views. After this PR, users can add, validate,
default, and revoke credentials in isolation from feed creation.

### PR 8 — Story 2: AI extraction profile + UI gate

**Tasks**: T047, T048, T049, T050, T051, T052, T053, T054, T055, T056.

The three LLM stages (`Loader::LlmLoader`,
`Processor::PassthroughProcessor`, `Normalizer::LlmNormalizer`), the
`LlmWebsiteExtractorMatcher`, the `llm_website_extractor` profile
entry, AI failure-mode mapping in `FeedPreviewService`, the
credential-gate partial, the cost message, and the system test.
Story 2 ships.

### PR 9 — Story 3: Handle / search-query inputs

**Tasks**: T057, T058, T059, T060, T061, T062.

The handle and query matchers, the two AI profile entries, the
candidate-chooser helper for plain-language non-URL descriptions,
and the Story 3 system test. Story 3 ships.

### PR 10 — Polish & cross-cutting

**Tasks**: T063, T064, T065, T066, T067, T068.

Vocabulary firewall system test, state-gating system test,
reload-doesn't-rerun test, edit-rerun test, full
`bin/rubocop -f github` pass, and the `quickstart.md` drift check.

## Dependency notes

- PR 4 → PR 5 are sequential (PR 5 wires PR 4's partials into the form).
- PR 6 → PR 7 → PR 8 are sequential — each unlocks the next.
- After PR 5 lands, PR 6 can start in parallel with the MVP release;
  PR 5 and PR 6 only collide in `feed_preview_service.rb` (PR 8's
  T052) and `_form_expanded.html.erb` (PR 8's T054–T055).
- PR 9 depends on PR 8 (reuses `LlmClient` and the three LLM stages).
- PR 10's tests each depend on the story they assert against;
  the rubocop / quickstart-drift sweep is last.
