# Unify the feed preview stack

**Date:** 2026-05-24
**Status:** Approved framing, pending spec review

## Problem

There are two parallel feed-preview subsystems that have drifted apart:

1. **Legacy / "admin" stack** — `FeedPreviewsController` (`/previews`) →
   persisted `FeedPreview` model → `AdminFeedPreviewJob` → `FeedPreviewWorkflow`.
   URL-only (`params[:url]`, `validates :url, presence`). Reachable only from the
   feed **show page** "Preview" button. The "Admin" name is misleading — it has
   nothing to do with an admin UI area.

2. **Smart-feed-creation / live stack** — `Feeds::PreviewsController`
   (`feed_live_preview_path`) → cache-only `FeedPreviewService` → `FeedPreviewJob`.
   `input_shape`-aware (url / query), credential-gated, and mints a
   stateless `PreviewToken` that gates `Feed#enable`. Drives the live preview pane
   on the create/edit form.

Two controllers, two jobs, two result representations (DB row vs cache entry vs
HMAC token), and two notions of "what proves a preview happened." The legacy
stack additionally fails silently for non-URL profiles.

## Goal

**One preview stack**, persisted as `FeedPreview`, that accepts feed data, works
in the new-feed form before submission, supports every profile shape (including
AI), and serves as the proof that gates enabling a feed.

## Key decisions (already agreed)

- **Keep `FeedPreview` as the persistent store.** A persisted preview is a
  referenceable artifact: it survives cache eviction, is inspectable, and can
  *be* the enable-gate proof. Generalize it beyond URL-only.
- **Do not merge the workflows.** Preview is not a kind of refresh. The shared
  units (`feed.loader_instance` / `processor_instance` / `normalizer_instance`)
  already live on `Feed`. `FeedRefreshWorkflow` stays untouched; preview keeps its
  own small workflow that orchestrates load→process→normalize in memory and stops.
  No base class, no `preview:` boolean threaded through the publish/persist path —
  reaching Freefeed-publish from a preview must be impossible *by construction*.
- **AI previews are in scope, with one caveat (Codex review).** The same
  load→process→normalize runs for AI and non-AI feeds; AI profiles differ only in
  that the loader/normalizer call `LlmClient.for(feed)`, which resolves
  `feed.llm_credential` or the user's active default. No special workflow code.
  Missing credential raises `LlmClient::CredentialMissing`, which becomes a failed
  preview. **Resolved in PR #440:** `Loader::LlmLoader#rendered_prompt` now renders
  from `feed.source_input` via a single `{{input}}` placeholder, and the
  `llm_handle_search` profile / `:handle` input_shape were removed (a handle is
  just a query for `llm_web_search`). The remaining AI item for this work is the
  active-credential gate (see the dedicated AI section, Task G2).
- **Delete `PreviewToken`.** With persisted previews, the enable gate becomes a
  freshness query against `FeedPreview` instead of verifying an HMAC token.

## Target architecture

```
form / show page
      │  POST profile_key + params (+ feed_id?)
      ▼
FeedPreviewsController#create
      │  builds a validated transient Feed
      │  upserts a FeedPreview (status: pending) keyed by params_digest
      │  enqueues FeedPreviewJob
      ▼
FeedPreviewJob#perform(feed_preview_id)
      │
      ▼
FeedPreviewWorkflow.new(feed_preview).execute
      │  load → process → normalize (in memory, on a transient Feed)
      │  writes status: ready + data, or status: failed
      ▼
FeedPreviewsController#show (polled via turbo_stream)
      │  renders ready / processing / failed partials
      ▼
Feed#enable gate
      │  queries: ready FeedPreview for (user, profile_key, params_digest)
      │  created within EXPIRY?
```

## Components

### `FeedPreview` model (generalize)

Today: `url` (not null), `feed_profile_key`, `status`, `data` (jsonb), `user_id`.

Changes:
- Add `params` jsonb (`null: false, default: {}`) — the source, input-shape
  agnostic (`params["url"]` / `["query"]`).
- Add `params_digest` string — canonical SHA256 of `params`, for the enable-gate
  lookup. **Unique** index on `[user_id, feed_profile_key, params_digest]` so a
  given (user, profile, source) has exactly one preview row to upsert and read.
- Add `ready_at` (datetime, nullable) — set when the workflow finalizes a preview
  to `ready`. The enable-gate freshness window is measured from `ready_at`, **not**
  `created_at`: a row can sit `pending` for a while before normalization completes,
  and `created_at` would distort the window. (Codex review.)
- Remove the `url` column and its presence/uniqueness/format validations; source
  now lives in `params`. Update `for_cache_key` scope accordingly (or replace with
  a `params_digest`-based finder).
- Keep `status` enum and `data` jsonb. Keep `posts_data` / `posts_count`.
- `belongs_to :user` already exists; add `has_many :feed_previews` on `User` so
  reads can be user-scoped (see controller + gate below).
- Migration must be reversible (up/down). Existing rows are ephemeral previews and
  may be discarded by the migration.

**Concurrency (Codex review).** Force-refresh resets a row to `pending` and
re-enqueues. A stale job from a prior run must not later mark the row `ready` and
overwrite a newer result. Carry a per-run token: store a `run_id` (uuid) on the
row when (re)enqueuing, pass it to the job, and have the workflow finalize with a
conditional update (`WHERE id = ? AND run_id = ?`). A no-op update means a newer
run superseded this one — discard. The unique index also prevents duplicate rows
racing into existence.

`params_digest` is computed with the same canonicalization currently in
`PreviewToken.params_digest` / `Feeds::PreviewsController#params_digest`
(deep-stringify → sort → JSON → SHA256). Extract it to one place
(e.g. a model method or small helper) so the writer and the enable-gate reader
agree.

### Single controller — `FeedPreviewsController`

Consolidated from both controllers. Top-level `resources :feed_previews,
only: [:create, :show, :destroy]` (path `previews`).

- `create` — accepts `profile_key` + `params` (+ optional `feed_id` for an
  existing feed). Builds a **validated transient `Feed`** (`profile_key`, `params`,
  `user`, and `llm_credential` resolved for AI profiles). If the source input for
  the profile's `input_shape` is blank, render the empty/cleared state (today's
  `source_input_blank?` behaviour). Upsert a `FeedPreview` keyed by
  `(user, profile_key, params_digest)`, enqueue `FeedPreviewJob`, render the
  loading state. A `force_refresh`/recompute path resets an existing preview to
  `pending` and re-enqueues (replaces today's `update` action + the cache-bust).
- `show` — looks up the `FeedPreview`, responds to `turbo_stream` (poll) and
  `html`. Renders ready / processing / failed states.
- `destroy` — clears the preview pane (today's live-stack `destroy`).

**User-scope every lookup (Codex review — IDOR).** The legacy controller does
`FeedPreview.find(params[:id])`, which is not user-scoped; with persisted rows
that exposes any user's preview by id. `show`/`destroy`/`create` must read through
`Current.user.feed_previews` (or `FeedPreview.where(user: Current.user)`), never a
bare `FeedPreview.find`.

The "draft" sentinel (`DRAFT_FEED_ID`) is no longer needed: a draft preview is
simply a `create` with `params` and no `feed_id`.

Credential gate: keep a "no usable credential yet" check for AI profiles
(today's `needs_credential_gate?` / `user_has_usable_credential?`) so AI previews
show a helpful prompt instead of a failed preview when the user has no active
credential.

### Job — rename `AdminFeedPreviewJob` → `FeedPreviewJob`

- Keep the DB-backed job (finds the `FeedPreview`, runs `FeedPreviewWorkflow`).
- Keep its `LlmClient::CredentialMissing` rescue (mark failed, swallow, no retry).
- **Delete** the cache-based `FeedPreviewJob` (the one wrapping `FeedPreviewService`).
- Net: one job named `FeedPreviewJob`.

### Workflow — keep `FeedPreviewWorkflow`, delete `FeedPreviewService`

- `FeedPreviewWorkflow` already does load→process→normalize in memory on a
  transient `Feed` and writes `status`/`data` to the `FeedPreview`. Adjust it to:
  - Build the transient `Feed` from `feed_preview.params` (not just `url`) +
    `feed_profile_key` + `user` + resolved `llm_credential`.
  - Keep the normalized-post JSON shape it already writes into `data`.
- **Delete** `FeedPreviewService` and its `Preview` / `PostDraft` Data types and
  token minting. Any consumers (the form pane, integration tests) move to the
  persisted `FeedPreview` + workflow.
- `FeedRefreshWorkflow` is untouched.

### Enable gate — replace `PreviewToken` with a `FeedPreview` lookup

- `Feed#enabling_requires_recent_preview` (runs on `save(context: :enable)`)
  becomes: "exists a `ready` `FeedPreview` for `(user_id, feed_profile_key,
  params_digest(params))` with `ready_at` within `EXPIRY`?" — add the error
  otherwise. Scope the query to the feed's `user`.
- **Preserve the exact current trigger surface (Codex review, pushed back).**
  Codex flagged that `FeedStatusesController#enable` uses `feed.enabled!`, which
  bypasses `save(context: :enable)` and therefore the gate. That bypass exists
  *today* with the token and is **intentional**: per the `feed.rb` comment, only a
  user-initiated promotion through the form re-proves a preview; operational
  re-enable of an already-vetted feed does not. The DB-query gate must keep this
  surface identical — gate `Feed#enable` only, do **not** newly gate the status
  toggle. No behaviour change here; just don't regress it.
- **Proof binds source only, by design.** The gate binds `(user, profile_key,
  params)` — same as the token does today. Schedule, target group, access token,
  and selected LLM credential are deliberately outside the preview proof. State
  this explicitly so it isn't mistaken for an oversight.
- **Delete** `PreviewToken`, `Feed#preview_token` attr, the hidden
  `preview_token` field in `feeds/_preview.html.erb`, and the
  `@feed.preview_token = params[:preview_token]` plumbing in `FeedsController`
  (create + update).
- `EXPIRY` (60 min) moves to wherever the freshness window is owned (Feed or
  FeedPreview constant).

### Views

- **Keep one set** of preview partials driven by the unified controller's
  `turbo_stream` responses (ready / processing / failed + credential gate).
  Consolidate the legacy `app/views/feed_previews/*` and live
  `app/views/feeds/_preview*` / `app/views/feeds/previews/*` into one coherent set;
  delete the duplicates.
- **Form pane** (`feeds/_form_expanded.html.erb`): repoint the `feed-preview`
  turbo-frame at the unified controller. Fix the hardcoded
  `params: { url: feed.url }` to use `feed.source_input` under the profile's
  `input_shape` (so query feeds preview correctly).
- **Show page** (`feeds/show.html.erb`): per earlier discussion the show-page
  preview is *not* required. Default: **drop the show-page Preview button**;
  preview lives in the create/edit flow. (If we later want it back, it can render
  the same unified pane.)

### AI profiles (Codex review)

The pipeline is credential-driven. Two limitations were surfaced in review:

- **Prompt rendering is URL-only.** ✅ **Done in PR #440.** `rendered_prompt` now
  renders from `feed.source_input` through a single `{{input}}` placeholder (all
  LLM templates standardized on it), and the `:handle` shape / `llm_handle_search`
  profile were removed. Non-URL AI profiles (now just `llm_web_search`) render
  correctly in both preview and refresh.
- **Active-credential check.** `LlmClient.for(feed)` returns `feed.llm_credential`
  without checking it's active (only the user-default fallback path filters by
  `active`). The controller credential gate (`needs_credential_gate?` /
  `user_has_usable_credential?`) must treat an inactive attached credential as
  "no usable credential," matching `Feed#llm_credential_required_when_enabled_ai_profile`.

### Routing

- Remove the nested `resource :preview, controller: "feeds/previews",
  as: :live_preview`.
- Keep/define `resources :feed_previews, only: [:create, :show, :destroy],
  path: "previews"`.
- Update all path helpers (`feed_live_preview_path` → `feed_previews_path` /
  `feed_preview_path`).

## Error handling

- Workflow failure (`load`/`process`/`normalize`, including
  `LlmClient::CredentialMissing`) → `FeedPreview` marked `failed`; the job's
  rescue keeps credential-missing quiet (info log, no retry, no error report) and
  reports unexpected errors via `Rails.error`.
- Missing credential for an AI profile is gated in the controller *before*
  enqueuing where possible (nicer UX), and defended in the job as a fallback.
- Enable without a fresh ready preview → validation error on `:state`
  (`:preview_required`), same UX as today.

## Testing

- **Reuse/rename:** `admin_feed_preview_job_test` → `feed_preview_job_test`
  (DB-backed); fold/replace the old cache-based `feed_preview_job_test`.
- **Model:** update `feed_preview_test` for `params`/`params_digest` and the
  dropped `url` column; verify migration up/down.
- **Controller:** merge `feed_previews_controller_test` and
  `feeds/previews_controller_test` into one suite covering create (draft +
  existing feed), show polling, blank-source, credential gate, destroy, and
  unsupported/invalid input.
- **Enable gate:** rewrite the ~40 `preview_token` references in `feed_test`,
  `feeds_controller_test`, and the `smart_feed_creation_*` / `feed_draft_flow` /
  `state_gating` integration tests to seed a `ready` `FeedPreview` (fresh /
  stale / wrong-params) instead of signing tokens. Delete `preview_token_test`.
- **AI:** add a preview test for an AI profile (credential present → ready;
  absent → failed/gated).
- Add `data-key` hooks for new/changed partials per project convention.

## Deletions (summary)

- `app/controllers/feeds/previews_controller.rb`
- `app/services/feed_preview_service.rb` + the old cache `FeedPreviewJob`
- `app/services/preview_token.rb` + `test/services/preview_token_test.rb`
- `Feed#preview_token` attr + `preview_token` form field + controller plumbing
- Duplicate preview views
- Show-page Preview button (default)

## Retention / cleanup (in scope — Codex review)

The cache TTL is going away, so persisted previews would accumulate forever.
A minimal retention policy ships **with this work** (same PR stack), not as an
open-ended follow-up: a recurring SolidQueue job that deletes `FeedPreview` rows
older than a retention window (e.g. `created_at < N days ago`), comfortably larger
than the enable `EXPIRY`. Drift-guard for the pipeline (below) can stay a
follow-up; storage growth cannot.

## Drift guard between preview and refresh (Codex review)

Codex agreed not to introduce a shared base class or `preview:` flag, and noted
the drift risk is best handled with **shared tests/fixtures** exercising the
`loader → processor → normalizer` behaviour both paths rely on, rather than
inheritance. Add or designate such shared coverage so the two orchestrations can't
silently diverge on the part they genuinely share.

## Out of scope / follow-ups

- Extracting a thin `FeedPipeline` collaborator between preview and refresh —
  optional refinement, composition only, only if shared tests prove insufficient.
- Re-introducing a show-page preview affordance if desired later.

## Review notes

Architecture reviewed by Codex (gpt-5.5) on 2026-05-24. Verdict: direction sound,
approved with blockers folded in above — user-scoped reads (IDOR), preserved
enable-gate trigger surface, concurrency/run-id for reused rows, `ready_at`-based
freshness, in-scope retention, and the AI prompt-rendering / active-credential
caveats. One Codex framing ("gate every enable path") was narrowed to "preserve
the current trigger surface" because the status-toggle bypass is intentional and
pre-existing.
