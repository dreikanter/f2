# Feed Preview Consolidation — Session Handoff

Last updated: 2026-05-25. Read this first when resuming the preview work.

## Where things stand

| PR | What | Status |
|----|------|--------|
| #440 | Drop `llm_handle_search` profile + `:handle` shape; render LLM prompts via a single `{{input}}` placeholder | **Merged** |
| #441 | Clean up leftover `:handle` references (strong params, test validator, comments) | **Merged** |
| #442 | **The backend consolidation** (branch `preview-consolidation`) | **Open — awaiting review/merge** |

After #442 merges, two pieces remain: **PR3 (retention job)** and the **manual-preview follow-up**. Details below.

## What #442 delivers (the "initial refactoring")

One persisted preview stack, replacing the old split DB/cache stacks:

- **`FeedPreview`** generalized: `feed_profile_key` + `params` (jsonb) + `params_digest` + `ready_at` + `run_id`; unique index on `(user_id, feed_profile_key, params_digest)`. The URL-only column is gone.
- **Identity = the user's source input**, not the whole params hash. `FeedPreview.digest_for(profile_key, params)` hashes only the value behind the profile's `input_shape` (one field today). Derived params don't affect identity. (The column is still named `params_digest`; it digests only the source — documented in the model. Optional rename to `source_digest` later; no prod DB.)
- **One singular controller** `FeedPreviewsController` (`feed_preview_path`, routes `only: [:show, :create]`): `show` finds-or-creates the row for `(user, profile, source)` and enqueues when it needs a run; `create` forces a refresh. User-scoped. Guards (blank/unknown source, AI credential gate) live in a `before_action`. No `@preview` ivar — values flow through returns.
- **One `FeedPreviewJob` → `FeedPreviewWorkflow`**, run-guarded: transitions use `FeedPreview.where(id:, run_id:).update_all(...)` so a superseded run can't finalize, and the workflow aborts early (via `Workflow::HaltExecution`) if its run was superseded.
- **Enable gate is a DB freshness query** — `Feed#enabling_requires_recent_preview` → `FeedPreview.fresh_ready(... within: Feed::ENABLE_PREVIEW_WINDOW)` (60 min). `PreviewToken`, `FeedPreviewService`, and the nested `Feeds::PreviewsController` are deleted.
- **Credential gate keeps the "save as draft & add credentials" behavior** (`FeedsController#gate_commit?`), now rendered by the unified pane.
- **Polling busy-loop fixed** (`65b9e5c`): the pane uses a stable polling host (`show.html.erb`) that swaps only `#feed-preview-body`; `ready`/`failed` bodies carry `data-preview-done` to trip the poller's stop-condition. Matches the `access_tokens`/`llm_credentials` poller pattern.

Reviewed holistically by Codex (architecture sound; robustness fixes folded in: create-race recovery, stale-ready refresh, unknown-profile guard, run-id guard). Full suite green (1451 runs, 0 failures, 1 skip). Net diff is negative.

## Decision: auto-preview is being removed

The current form **auto-previews** the recommended candidate the moment the expanded form appears (a lazy turbo-frame). We are **replacing this with on-demand preview** in the follow-up. Reasons: avoids spending AI tokens before the user decides, removes fragile candidate-switch wiring, and fixes the multi-candidate enable problem.

#442 keeps the auto-preview pane as the **interim** (so feeds remain previewable→enablable until the follow-up lands), with the busy-loop fixed.

### Known interim limitations in #442 (do NOT fix in #442 — the follow-up deletes them)
- **"Refresh preview" button and candidate-switch re-preview are dead.** The Phase D+E rewrite simplified the form pane to a bare `turbo_frame` and dropped the `data-controller="preview"` + `data-preview-target="frame"` wiring that `preview_controller.js` needs. Single-candidate happy path works; multi-candidate switching won't update the live preview.
- **Multi-candidate enable gap:** only the recommended candidate gets auto-previewed, so enabling a *switched* (non-recommended) candidate is blocked by `fresh_ready` (no preview for it). The manual-preview follow-up resolves this by previewing whatever profile is currently selected.

## Remaining work

**Order (decided): 1) merge #442 → 2) PR3 (retention job) → 3) manual preview.** The two
are independent (no shared files of note), so this is a priority choice, not a
dependency. PR3 is the quick win and goes first; the manual-preview follow-up —
which also closes #442's interim multi-candidate/refresh gaps — comes after.

### PR3 — `FeedPreview` retention/prune job (small, independent)
Spec: `plan.md` Phase H. Add `PruneFeedPreviewsJob` deleting rows older than a window comfortably larger than `Feed::ENABLE_PREVIEW_WINDOW` (e.g. `created_at < 7.days.ago`), schedule it in `config/recurring.yml` (dev + prod), with a test. Branch from `main` after #442 merges. The unique key bounds row growth to (user × profile × source), but the cache TTL is gone, so this still ships.

### Follow-up PR — Manual preview (the bigger one)
Replaces auto-preview. Recommend running it through brainstorming → spec → plan (likely `specs/004-manual-feed-preview/`).

Requirements (from the product owner):
- **Manual Preview button** in the expanded feed form — **both `new` AND `edit`** (edit currently renders no preview at all — new scope, gated by `unless edit_mode`).
- **Button availability is dynamic** (Stimulus), driven by form state: enabled only when a profile is selected *and* the feed is previewable. ⚠️ `Feed#can_be_previewed?` is URL-centric (`url.present?`) — wrong for query-shaped profiles; gate on `source_input` present instead (generalize `can_be_previewed?` or add a source-based check, the same way `source_input`/`digest_for` were generalized).
- **Click → popup/modal** that polls the backend until the preview is ready, then renders it in the popup.

Delete in the follow-up: the lazy auto-preview frame in `app/views/feeds/_form_expanded.html.erb`, the `candidate_chooser → preview` re-point wiring (`candidate_chooser_controller.js` dispatch + `preview_controller.js` `_onCandidateChanged`), and the inline auto-running pane. Reuse/relocate the pane partials (`ready`/`processing`/`failed`/`credential_gate`) into the popup.

Backend needs no change — `show`/`create` + the job + the `fresh_ready` gate are trigger-agnostic; the popup just drives them (poll `show` with `format: :turbo_stream`; `create` to (re)start). Keep the stable-host polling structure.

**Verify in a real browser** (the `verify`/`playwright-cli` flow). The test suite has no JS/system coverage — it did not catch the polling busy-loop or the broken refresh/candidate-switch. Don't rely on it for the popup/poll/button-state behavior.

## Working conventions (carry over)
- Branch per PR from `main`; the user reviews and merges each PR before the next is started.
- `bin/rails test` + `bin/rubocop -f github` before every commit; atomic commits, imperative subjects ≤50 chars.
- Ask Codex for review on substantial changes (architecture + robustness, not just style).
- Front-end changes need browser verification, not just the suite.

## Orientation — key files
- `app/controllers/feed_previews_controller.rb` — singular preview resource
- `app/models/feed_preview.rb` — `digest_for` / `source_input` / `fresh_ready`
- `app/services/feed_preview_workflow.rb` — run-guarded pipeline; `app/services/workflow.rb` — `HaltExecution`
- `app/jobs/feed_preview_job.rb`
- `app/models/feed.rb` — `enabling_requires_recent_preview`, `ENABLE_PREVIEW_WINDOW`, `source_input`, `source_input_shape`
- `app/views/feed_previews/` — `show` (polling host) + `_ready` / `_processing` / `_failed` / `_credential_gate`
- `app/views/feeds/_form_expanded.html.erb` — the interim auto-preview frame (to be replaced by the manual button)
- `app/javascript/controllers/polling_controller.js` — shared poller (polls immediately on connect; stop-condition based)
- `config/routes.rb` — `resource :feed_preview, only: [:show, :create]`
- `specs/003-unify-feed-preview-stack/{spec,plan}.md` — design + task plan (Phase G1 done in #440; Phase H = PR3; manual-preview decision supersedes the auto-preview view work in the plan)
