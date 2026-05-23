# Implementation Plan: Feed Drafts

**Date**: 2026-05-23 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `/specs/002-feed-drafts/spec.md`

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps in [`tasks.md`](./tasks.md) use checkbox (`- [ ]`) syntax for tracking.

## Summary

Adds a `draft` state to `Feed` so feed creation can be interrupted at any point and resumed later. The change touches three concentric rings of the existing code:

1. **Model layer** — `Feed.state` enum gains a `draft` value; the unconditional `name: presence` becomes conditional on `enabled?`; the existing `if: :enabled?` guards on `cron_expression`, `access_token`, and `target_group` stay; a new conditional `llm_credential` presence guard fires for AI profiles when enabled. The `llm_credential_belongs_to_user` validator is dropped; ownership for both `llm_credential_id` and `access_token_id` is enforced at the controller seam via scoped lookup.
2. **Controller / form layer** — the expanded form gets an "Enable feed" checkbox separate from a single "Save feed" button. `FeedsController#create` and `#update` attempt a single save at the target state derived from the checkbox; on enabled-envelope failure, they fall back to saving the data anyway (as draft for new records, as the prior state for existing) and re-render the form with the captured enabled-envelope errors. The previous "always two-step save-then-promote" pattern is explicitly avoided because it self-skips the preview-token gate. Source-side fields (`url`, `feed_profile_key`, `params`) are permitted to be edited while `feed.draft?`, locked thereafter.
3. **Credential round-trip layer** — the `?input=<URL>` plumbing recently added to `LlmCredentialsController` / `LlmCredentials::ValidationsController` / `Feeds::PreviewsController` / `_credential_gate.html.erb` is removed and replaced with `?feed_id=<id>`. The credential gate becomes a form-submit (not a navigation link) that persists the in-progress feed as a draft before redirecting to credential setup. On credential create, the credential is auto-attached to the originating draft. When the credential reaches `active`, the show partial surfaces a "Continue setting up your feed" link to `edit_feed_path(feed_id)`.

A fourth thin ring — feed list rendering — adds the "Draft" badge, the nameless-draft fallback label (via `feed.source_input`), a third bucket in the index summary line, and softer discard confirmation copy.

## Technical Context

**Language/Version**: Ruby (pinned in `.ruby-version`, managed by mise)

**Primary Dependencies**: Rails edge, Turbo, Stimulus, Tailwind, ViewComponent, Pundit, SolidQueue. No new dependencies.

**Storage**: PostgreSQL. One schema-only migration (`feeds.state` numeric remap + default change). No data backfill (app is pre-production, dev DB reset on cutover).

**Testing**: Minitest (`bin/rails test`) with FactoryBot. Tests travel with code in the same commit (constitution principle II).

**Constraints**:
- Migration is reversible (constitution requirement) but no data backfill needed.
- All `Rails.error.report` for handled exceptions stays (principle V).
- Atomic commits (principle III) — one task = one commit; each commit leaves the suite green and rubocop clean.

**Scale/Scope**: 26 functional requirements (FR-001 through FR-026, plus FR-014a/FR-022a/FR-023a). 6 phases below. New LOC budget ≈ 400–700 (including tests).

## Constitution Check

| Principle | How this plan complies |
|---|---|
| I — Atomic commits | Each task in `tasks.md` is one commit; phases are landable as separate PRs. |
| II — Tests travel with code | Each implementation task includes its tests in the same commit. |
| III — Reversible migrations | The single migration is reversible (numeric remap is symmetric; default-flip reverses); no data backfill on either direction since dev DB resets. |
| IV — Standard Rails conventions | No new architectural patterns; all changes use existing Feed/Controller/View seams. |
| V — `Rails.error.report` for handled exceptions | No new exception sites introduced; existing report sites unchanged. |

## Project Structure

### Documentation (this feature)

```
specs/002-feed-drafts/
├── spec.md        — requirements, user stories, acceptance criteria, FR-001..FR-026
├── plan.md        — this file (architecture + approach)
└── tasks.md       — phased actionable task list (T001, T002, ...)
```

### Source Code touched

**Migrations** (create):
- `db/migrate/YYYYMMDDHHMMSS_change_feed_state_to_three_value_enum.rb`

**Models** (modify):
- `app/models/feed.rb` — enum, default, conditional `name` validator, `draft?`/`ready_to_enable?` predicates, llm_credential conditional validator, drop `llm_credential_belongs_to_user`.

**Controllers** (modify):
- `app/controllers/feeds_controller.rb` — single-save-at-target with fallback, state-aware permits, ownership scoping for both `llm_credential_id` and `access_token_id`, draft count for index, gate-commit handling.
- `app/controllers/llm_credentials_controller.rb` — accept `feed_id`, auto-attach at create, pass through.
- `app/controllers/llm_credentials/validations_controller.rb` — pass `feed_id` through polling.
- `app/controllers/feeds/previews_controller.rb` — pass `feed_id` to credential gate instead of `input`.

**Views** (modify):
- `app/views/feeds/_form_expanded.html.erb` — Enable checkbox + Save feed button; source-side editability gated on `feed.draft?`; credential gate becomes a form-submit `<button>` inside the form.
- `app/views/feeds/_credential_gate.html.erb` — `input:` local → `feed_id:` (in `feed_id`-aware variant rendered from the form); button label "Add AI credentials" with the help-text side-effect message.
- `app/views/llm_credentials/new.html.erb` — form action carries `feed_id`.
- `app/views/llm_credentials/show.html.erb` — polling endpoint carries `feed_id`.
- `app/views/llm_credentials/_show_content.html.erb` — strict locals `feed_id:`; "Continue setting up your feed" button points to `edit_feed_path(feed_id)`, visible only when `active`.
- `app/views/feeds/index.html.erb` — render 3-bucket summary including drafts.

**Helpers / Components** (modify):
- `app/helpers/feed_helper.rb` — `feed_summary_line` supports a `draft_count:` bucket; `feed_status_icon` covers `:draft`.
- `app/components/feeds_list_component.rb` — fallback to `feed.source_input` (or "Untitled draft") when name blank; pass status icon for draft.

**Stimulus** (modify, possibly remove):
- `app/javascript/controllers/feed_form_controller.js` — strip the existing submit-button label swap (no longer needed); keep only what's still useful.

**Tests** (create/modify):
- `test/models/feed_test.rb`
- `test/controllers/feeds_controller_test.rb`
- `test/controllers/llm_credentials_controller_test.rb`
- `test/controllers/llm_credentials/validations_controller_test.rb`
- `test/components/feeds_list_component_test.rb`
- `test/helpers/feed_helper_test.rb`
- `test/integration/feed_draft_flow_test.rb` (new — end-to-end save/resume/enable + gate round-trip)

### Approach

Six phases, runnable independently as PRs (with phase ordering reflecting dependency):

1. **Phase 1** — Adjacent cleanup (ownership scoping). Independent of state changes. Lands first because it's a precondition for safe refactoring and is small.
2. **Phase 2** — State enum + audit. Schema migration, enum/default change, hardcoded-integer audit. Foundation; everything else depends on this.
3. **Phase 3** — Validation envelope split. Relaxes `name`; adds conditional `llm_credential` validator. Depends on Phase 2.
4. **Phase 4** — Form behavior + save handler. Checkbox + Save button; single-save-at-target with fallback; source-side editability. Depends on Phase 3.
5. **Phase 5** — Credential round-trip refactor. `?input=` → `?feed_id=`; auto-attach; gate becomes form-submit. Depends on Phase 4 (form is the entry to the gate).
6. **Phase 6** — List polish. Badge, fallback label, summary count, discard copy. Depends on Phase 2 (state) but can run in parallel with Phases 3–5.

`tasks.md` enumerates each task with file paths and acceptance criteria.

## Complexity Tracking

| Risk | Mitigation |
|---|---|
| Hardcoded enum integer in `FeedsController` sortable status SQL | FR-026 / T201 audits all literal integer references; the SQL fragment is rewritten. |
| Preview-token validator silently neutralized by save-then-promote | Spec FR-012/FR-013 explicitly forbid the two-step pattern; the controller uses single-save-at-target. Test coverage in Phase 4 includes "create-and-enable on new feed requires preview token." |
| Default flip breaking unrelated code paths | FR-001 audit. Factories already set state explicitly; seeds/console scripts checked in T204. |
| Two-gate UX asymmetry (Freefeed token gate still dead-ends) | Tracked as follow-up [#424](https://github.com/dreikanter/f2/issues/424); spec out-of-scope section calls out the trade-off. |

## Notes

- The single migration changes both schema default and numeric mapping. Even with no data backfill, the test suite running locally with an existing dev DB needs `bin/rails db:reset` (or `db:migrate:reset`) once on cutover.
- `_form_expanded.html.erb` already has a Stimulus `feed-form` controller wired up that swaps the submit-button label based on the "Enable feed" checkbox. After this work the submit label is always "Save feed"; that Stimulus behavior is removed (the controller may still be needed for the groups refresh — keep only what's actually used).
- The `_blocked_no_tokens.html.erb` template is unchanged in this spec; the same draft round-trip pattern can be applied later per [#424](https://github.com/dreikanter/f2/issues/424).
