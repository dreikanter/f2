# Manual feed preview

**Date:** 2026-05-25
**Status:** Approved framing, pending spec review

## Problem

The feed form currently **auto-previews** the recommended candidate the moment
the expanded form appears (a lazy turbo-frame). This was kept as the interim in
#442, but it has real costs:

- It spends AI tokens before the user has decided to commit to a feed.
- The candidate-switch and "Refresh preview" wiring it depends on is fragile and
  already half-broken after the #442 rewrite (`preview_controller.js`'s frame
  target and the `feed:candidate-changed` dispatch are dead).
- Only the recommended candidate gets previewed, so previewing a *switched*
  candidate doesn't work.
- The `edit` form renders no preview at all.

The backend was unified and made trigger-agnostic in #442 (`FeedPreviewsController#show`
find-or-create + poll, `#create` force-refresh, the run-guarded `FeedPreviewJob` /
`FeedPreviewWorkflow`). What remains is the front-end: replace auto-preview with an
explicit, on-demand preview the user opens when they want it.

## Goal

Preview is an **optional, user-initiated step**: a "Preview" button on the feed
form (both `new` and `edit`) opens a popup that runs and polls the preview for
the currently selected profile + source, then shows the result. Previewing is
**decoupled from enabling** — a feed can be enabled whenever its required fields
are filled, whether or not the user previewed it.

## Key decisions (agreed)

- **Preview does not gate enabling.** Removed in this work: the
  `enabling_requires_recent_preview` validator and everything that exists only to
  serve it. Enabling requires only the standard checks (name, access_token,
  target_group, cron, and an active llm_credential for AI profiles), all already
  validated under the enabled envelope.
- **Reuse the existing backend unchanged.** `show` (find-or-create + poll),
  `create` (force refresh), the job, and the workflow are trigger-agnostic; the
  popup just drives them.
- **Reuse existing UI infrastructure:** `ModalComponent` + `modal_controller.js`,
  the `polling_controller.js` stable-host pattern, and the
  `feed_previews/_ready|_processing|_failed|_credential_gate` partials.
- **Persisted previews stay** (with the #442 reuse-within-window behavior and the
  PR3 retention sweeper). First open reuses a recent ready preview to save tokens;
  an in-popup "Refresh" forces a fresh run.

## Behavior

### Preview becomes optional (backend)

- Delete `Feed#enabling_requires_recent_preview` and its `validate … on: :enable`.
- Simplify `Feed#enable` to a plain `save` (keep the in-memory state rollback on
  failure so re-renders reflect DB truth).
- Delete the now-unused `FeedPreview.fresh_ready` and its tests; drop the
  `feed_test.rb` "preview_required" expectations and the related
  `feeds_controller_test.rb` note.
- Rename `Feed::ENABLE_PREVIEW_WINDOW` → `Feed::PREVIEW_FRESHNESS_WINDOW`. It no
  longer governs enabling; it only bounds how long a ready preview is reused
  before `FeedPreviewsController#stale_ready?` forces a re-run. Update the
  controller, its test, and the `PruneFeedPreviewsJob` comment.
- **Sweep all references** so the removed invariant can't creep back: controller
  + controller test, `feed_test.rb` and `feed_preview_test.rb`, the prune-job
  comment, and any prose that still describes a preview as "what proves a preview
  happened" / the enable proof (e.g. `specs/003-*` and `CLAUDE.md` if present).
  Spec 003 stays the historical record of what #442 shipped; only fix prose that
  describes *current* behavior.

### Previewability

- Generalize `Feed#can_be_previewed?` to `source_input.present? &&
  feed_profile_present?` (was `url.present?`), so query-shaped profiles work.
- Used to set the Preview button's initial server-rendered enabled/disabled state.

### Preview button (`app/views/feeds/_form_expanded.html.erb`)

- Replace the lazy auto-preview turbo-frame with a **"Preview" button**, placed
  where the old frame was (after the Name field), rendered in **both** `new` and
  `edit` modes (drop the `unless edit_mode` guard).
- A new Stimulus controller (`preview_button`) keeps the button's `disabled`
  state in sync with form state: enabled only when a profile is selected (checked
  candidate radio or the hidden `feed_profile_key` field) **and** the source is
  present. It listens for candidate-chooser selection changes.
- On click, the controller reads the current `profile_key` and source value,
  builds `feed_preview_path(profile_key:, params: { input_shape => source })`,
  points the popup's `feed-preview` turbo-frame at it, and opens the popup.
- **Param-key contract:** the `input_shape` is derived from the *selected*
  profile, not from the originally-rendered feed. Each candidate payload carries
  its `input_shape` (add it to the `candidates` JSON on `#feed-form`); the
  single-candidate case uses the feed's `source_input_shape`. Today all
  candidates for one classified input are the same shape, but deriving per-profile
  keeps switching candidates correct if that ever stops holding.
- **Edit mode** has no candidate chooser (source and profile are locked), so the
  button previews the feed's persisted `feed_profile_key` + `params` and reuses
  the same persisted `FeedPreview` row as create — a "check what this feed would
  post now" action.

### Preview popup

- Reuse `ModalComponent` (title: "Feed preview"), rendered **inside** the feed
  form so the credential-gate's "save as draft & add credentials" submit button
  still posts the form.
- The popup body holds `turbo_frame_tag "feed-preview"`. Setting its `src` loads
  `feed_previews/show` — the existing stable polling host — which polls until a
  terminal (`ready`/`failed`) body marks itself `data-preview-done`. The
  `_ready`/`_processing`/`_credential_gate` partials are reused; `_failed` is
  adjusted (see below).
- **Exactly one preview host exists on the page** (the popup's). The old lazy
  frame is removed, so the global `feed-preview` / `feed-preview-body` ids the
  turbo-stream updates target are unambiguous.
- **First open** uses `show` (reuses a recent ready preview within the freshness
  window — saves AI tokens). The in-pane **"Refresh preview"** button uses
  `create` (forces a fresh run; the frame reloads and the poller restarts because
  the new processing body has no `data-preview-done`).
- **Refresh wiring (fixed):** both "Refresh preview" (`_ready`) and "Try again"
  (`_failed`) are `type="button"` controls that POST `create` and then reload the
  `feed-preview` frame — locating it via `closest("turbo-frame#feed-preview")`
  rather than a Stimulus `frameTarget` (the current `preview_controller` reload is
  dead because no target is declared). This also removes the only `button_to` in
  the partials.
- **No `<form>` inside the preview partials.** The popup renders inside the feed
  form, so a nested `<form>` (e.g. `_failed`'s old `button_to`) would be invalid
  HTML. The only submit allowed is `_credential_gate`'s button, which deliberately
  posts the *outer* feed form ("save as draft & add credentials").
- **Closing the popup stops polling.** `ModalComponent` hides via CSS only, so
  Stimulus `disconnect` does not fire and a mid-`processing` poller would keep
  hitting the endpoint in the hidden popup. On close, the frame is cleared so the
  polling host unmounts (`disconnect` → `stopPolling`). Reopening re-points the
  frame at `show`, which reuses the now-ready row — so no work is lost. This
  preview-specific behavior lives in the preview controller, not in the shared
  `modal_controller`.

### Deletions / simplifications (front-end)

- The lazy auto-preview frame in `_form_expanded.html.erb`.
- `candidate_chooser_controller.js`'s `feed:candidate-changed` dispatch — the
  radios already submit `feed[feed_profile_key]` directly, so no JS is needed for
  selection to take effect.
- `preview_controller.js`'s `_onCandidateChanged` handler and `frameTarget`; the
  controller slims to refresh-only — POST `create`, then reload the frame located
  via `closest("turbo-frame#feed-preview")` (drives both `_ready` Refresh and
  `_failed` Try again).

### UX copy

Preview now reads as an optional confidence check, not a required step, and AI
token spend should be honest about when it happens:

- The amber AI cost notice currently says "AI fetches (including this preview)
  cost tokens." Since preview no longer auto-runs, drop the parenthetical and make
  the preview/refresh actions own the "this may spend tokens" message instead.
- The button reads as optional (e.g. "Preview" / "See what we'd post"); nothing
  implies the feed can't be saved or enabled without it.

## Non-goals

- No changes to `FeedPreviewsController`, `FeedPreviewJob`, or
  `FeedPreviewWorkflow` behavior.
- No change to how candidates are identified or rendered.
- No enable affordance inside the popup — the popup is purely informational.

## Verification

Browser-verified (playwright-cli / verify flow), since the test suite has no
JS/system coverage and did not catch the earlier polling busy-loop or the broken
refresh/candidate-switch:

- Button enables only when a profile is selected and source is present.
- Click opens the popup; it polls and renders the preview.
- "Refresh preview" and "Try again" force a fresh run and visibly re-render
  (the reload-via-`closest` path actually works).
- Closing the popup mid-`processing` stops the poller (no requests to the hidden
  popup); reopening shows the now-ready result.
- AI profile without an active credential shows the credential gate; its button
  saves the feed as a draft.
- Edit-mode form shows the same button and popup.
- A feed can be enabled and saved without ever opening the preview.

## Orientation — key files

- `app/models/feed.rb` — remove enable gate; generalize `can_be_previewed?`;
  rename the window constant; simplify `enable`.
- `app/models/feed_preview.rb` — remove `fresh_ready`.
- `app/controllers/feed_previews_controller.rb` — unchanged behavior; constant
  rename in `stale_ready?`.
- `app/views/feeds/_form_expanded.html.erb` — button + popup replace the frame.
- `app/views/feed_previews/{show,_ready,_processing,_credential_gate}.html.erb`
  — reused; `_failed.html.erb` drops its `button_to` for a JS-driven Try again.
- `app/views/feeds/_candidate_chooser.html.erb` / candidate builder — add
  `input_shape` to each candidate payload.
- `app/javascript/controllers/preview_button_controller.js` — new.
- `app/javascript/controllers/{preview,candidate_chooser}_controller.js` — slim down.
- `app/components/modal_component.*` — reused.
- `app/jobs/prune_feed_previews_job.rb` — comment update for the constant rename.
