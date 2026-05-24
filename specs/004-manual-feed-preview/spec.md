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
  builds `feed_preview_path(profile_key:, params: { source_input_shape => source })`,
  points the popup's `feed-preview` turbo-frame at it, and opens the popup.

### Preview popup

- Reuse `ModalComponent` (title: "Feed preview"), rendered **inside** the feed
  form so the credential-gate's "save as draft & add credentials" submit button
  still posts the form.
- The popup body holds `turbo_frame_tag "feed-preview"`. Setting its `src` loads
  `feed_previews/show` — the existing stable polling host — which polls until a
  terminal (`ready`/`failed`) body marks itself `data-preview-done`. The
  `_ready`/`_processing`/`_failed`/`_credential_gate` partials are reused as-is.
- **First open** uses `show` (reuses a recent ready preview within the freshness
  window — saves AI tokens). The in-pane **"Refresh preview"** button uses
  `create` (forces a fresh run; the frame reloads and the poller restarts because
  the new processing body has no `data-preview-done`).

### Deletions / simplifications (front-end)

- The lazy auto-preview frame in `_form_expanded.html.erb`.
- `candidate_chooser_controller.js`'s `feed:candidate-changed` dispatch — the
  radios already submit `feed[feed_profile_key]` directly, so no JS is needed for
  selection to take effect.
- `preview_controller.js`'s `_onCandidateChanged` handler; the controller slims
  to refresh-only (POST `create`, reload the `feed-preview` frame).

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
- "Refresh preview" forces a fresh run and re-renders.
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
- `app/views/feed_previews/{show,_ready,_processing,_failed,_credential_gate}.html.erb`
  — reused as-is.
- `app/javascript/controllers/preview_button_controller.js` — new.
- `app/javascript/controllers/{preview,candidate_chooser}_controller.js` — slim down.
- `app/components/modal_component.*` — reused.
- `app/jobs/prune_feed_previews_job.rb` — comment update for the constant rename.
</content>
</invoke>
