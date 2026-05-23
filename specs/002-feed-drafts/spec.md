# Feature Specification: Feed Drafts

**Created**: 2026-05-23

**Status**: Draft

**Input**: User description: "I want a clear draft state for the Feed record to enable an ability to interrupt new feed configuration at any moment, within reason. The use case I'm after is to start configuring a feed, navigate away to add an LLM API credentials, or may be add a new Freefeed API token, or add another feed. Then see the draft feed in the Feeds list, and continue editing it. It would be nice to be redirected back if the flow makes sense. The general idea is that the UI should not block user from achieving what they need. And the state of the system should be very clear at any moment."

**Builds on**: [`001-smart-feed-creation`](../001-smart-feed-creation/) — the smart-feed-creation flow established the entry point, identification, preview, and credential gate. This spec adds an interruptible-by-default lifecycle on top of that flow.

## Clarifications

### Session 2026-05-23

- Q: Should "draft" be a separate `state` enum value, a derived predicate, or a separate flag (e.g., `setup_completed_at`)? → A: Separate enum value. The lifecycle is constrained (`draft → enabled` forward-only, `enabled ⇄ disabled` free, no path back to `draft`); an enum encodes the state machine directly and keeps "where is this feed in its lifecycle" answerable from one column.
- Q: When does a draft get persisted to the DB? → A: Explicit submit of the form with "Enable feed" unchecked (saves as draft for new feeds, keeps existing drafts as drafts) + auto-save on interrupting actions (clicking the credential gate). Casual navigation away (clicking nav, browser back) does NOT save.
- Q: How do drafts surface in the feed list? → A: Mixed in with active feeds, distinguished by a "Draft" badge and a `[Continue setup] [Discard]` affordance per row. Clicking a draft opens the same form template used for new-feed creation, pre-filled.
- Q: Should source-side fields (`url` / `feed_profile_key` / `params`) stay editable on a draft? → A: Yes while draft, locked after first promotion to `enabled`. A draft is by definition the place where source is still being decided.
- Q: How are drafts cleaned up? → A: Manual delete only, with softer confirmation copy ("Discard this draft? No data will be lost since it hasn't been activated."). No background expiry, no per-user cap.
- Q: Should the "Enable" decision be a separate checkbox or part of the submit-button label? → A: Separate checkbox. The submit button is always "Save feed". The checkbox is always interactable; whether enabling succeeds is a server-side validation outcome, not a client-side gate.
- Q: What happens when the user clicks Save with the Enable checkbox checked but enabled-envelope validations fail? → A: The feed is persisted as a draft (the data the user typed is not lost) and the form re-renders with errors describing what prevented enabling.
- Q: Should `LlmCredentialsController` round-trip via `?input=<URL>` or `?feed_id=<id>`? → A: `?feed_id=<id>`. The current `?input=` plumbing (added in PR #422) gets replaced. The credential created during the round-trip auto-attaches to the feed.
- Q: Should `llm_credential_belongs_to_user` model validator stay where it is? → A: No. Authorization belongs at the controller seam, not in the model. Same for `access_token_id`. This cleanup is adjacent to the draft work and rides along with it.

## Why this exists

Today, creating a feed is an "all or nothing" interaction: the user paste-identifies a source and is presented with a configuration form. If they need to step away — to add an AI credential, to add a Freefeed access token, to handle something else — there is no way to save what they have. The credential gate that already exists in the preview pane links out to credential creation, but the in-progress feed is in-memory only; on return, the user re-types or re-pastes everything.

This breaks the principle that the UI should not block users from doing the next thing they need. It also creates an awkward dependency chain: "you can't follow this site until you have an AI credential, but to add an AI credential you must abandon what you were doing."

The feature introduces a first-class **draft** state on `Feed`. A draft is a feed whose configuration is in progress and that the user explicitly saved. Drafts are listed alongside active feeds (with a clear "Draft" badge) and can be resumed, finished, or discarded. The credential gate in the new-feed flow no longer navigates away — instead it saves the in-progress feed as a draft and round-trips back when the credential is ready, with the credential auto-attached.

The result: at every moment, the state of the user's work is visible (in the feed list, with a state badge) and resumable.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Save an in-progress feed and come back to it (Priority: P1)

A user starts configuring a new feed, pastes a URL, sees the expanded form with their identification results. Mid-way through filling in the target group and other settings, they realize they need to do something else first — switch tasks, look something up, whatever. They leave the **Enable feed** checkbox unchecked and click **Save feed**. The feed is saved as a draft. The user navigates to the Feeds list, sees the draft entry there with a "Draft" badge, and goes off to do whatever they needed to do. Some time later they return, click the draft in the Feeds list, and land back on the same form, pre-filled with everything they had typed. They finish the configuration, tick **Enable feed**, click **Save feed**, and the feed activates.

**Why this priority**: This is the core capability. Without it, none of the more specific flows (credential gate round-trip, etc.) make sense. Story 1 alone gives users an interruptible setup experience.

**Independent Test**: Start a new feed, paste a URL, fill in a name, leave "Enable feed" unchecked, and click "Save feed". Navigate to /feeds. Verify the draft appears with a "Draft" badge. Click it, verify all typed input is restored. Tick "Enable feed" and submit; verify the feed transitions to `enabled` and behaves like any other active feed.

**Acceptance Scenarios**:

1. **Given** I'm signed in and have identified a source for a new feed, **when** I click "Save feed" with partial configuration and "Enable feed" unchecked, **then** the feed is persisted with `state: draft` and I'm redirected to the feeds list with a confirmation that the draft was saved.
2. **Given** I have one or more drafts in my feed list, **when** I look at the feeds list, **then** each draft is visually distinguished by a "Draft" badge and shows `[Continue setup] [Discard]` affordances inline.
3. **Given** I'm on the feeds list, **when** I click "Continue setup" on a draft, **then** I land on the same expanded form template I used during creation, with all previously typed values restored, including the URL/profile that came from identification.
4. **Given** I'm editing a draft, **when** I change the URL field to a different value, **then** identification re-runs against the new URL and the form updates accordingly (source-side fields remain editable while the feed is in draft).
5. **Given** I'm editing a draft with all required fields filled in, **when** I check "Enable feed" and click "Save feed", **then** the feed transitions to `enabled`, the source-side fields lock from that point forward, and the feed begins running on its schedule.
6. **Given** I'm editing a draft, **when** I click "Discard" from the feed list (or "Delete" from the feed edit view), **then** the draft is destroyed after a light confirmation that explains no data will be lost.

---

### User Story 2 — Add AI credentials mid-flow without losing the in-progress feed (Priority: P2)

A user pastes a URL that requires AI extraction. The identification result selects an AI-backed profile. The user has no LLM credentials yet, so the preview pane shows the credential gate ("AI extraction needs your API key"). The gate's "Add AI credentials" button explains in help text that the in-progress feed will be saved as a draft. The user clicks it. Behind the scenes the in-progress feed is saved as a draft, and the user is taken to the AI credential creation form. They fill in the API key, submit, wait for the credential to validate (the existing pending → validating → active polling flow), and once it's active they see a "Continue setting up your feed" button. They click it and land back on their draft, with the freshly created credential already attached.

**Why this priority**: This is the headline value: the credential dependency no longer interrupts the feed creation flow. It depends on Story 1's draft plumbing.

**Independent Test**: Start a new feed pointing at an AI-extraction source, with zero LLM credentials. Verify the credential gate appears with help text mentioning the draft-save side-effect. Click "Add AI credentials"; verify a draft was saved (visible in /feeds) and the URL is `/llm_credentials/new?feed_id=<id>`. Complete credential creation, wait for active state, click "Continue setting up your feed"; verify return to `/feeds/<id>/edit` with the new credential pre-attached.

**Acceptance Scenarios**:

1. **Given** I'm configuring a new feed whose profile requires AI and I have no active LLM credentials, **when** the credential gate appears in the preview pane, **then** it shows a single "Add AI credentials" button with help text explaining "We'll save your feed as a draft so you can pick up where you left off."
2. **Given** the credential gate is visible, **when** I click "Add AI credentials", **then** the form submits as a save-as-draft (relaxed validation, source-side data preserved) and I'm redirected to `new_llm_credential_path(feed_id: <my draft's id>)`.
3. **Given** I land on the LLM credential creation form via the gate, **when** I submit valid credential parameters, **then** the credential is created, the validation job is enqueued, and I'm redirected to the credential show page (which carries `feed_id` through).
4. **Given** I'm on the credential show page while validation is pending, **when** the credential reaches `active` state, **then** a "Continue setting up your feed" link appears pointing to `edit_feed_path(feed_id)`.
5. **Given** I submit the LLM credential form with `feed_id` present, **when** the credential row is created, **then** the draft feed's `llm_credential_id` is set to the new credential's id at that moment, before validation completes (the user does not have to pick it from a dropdown on return, and the relationship is captured regardless of whether the credential ends up active or inactive).
6. **Given** I clicked "Add AI credentials" but the credential ends up `inactive` (validation failed), **when** I navigate back to my draft, **then** the inactive credential is still attached but the enabled-envelope validator catches it if I try to enable the feed (the alert tells me to fix or replace the credential).
7. **Given** I clicked "Add AI credentials" and then abandoned the credential flow (closed tab, navigated away), **when** I return to the feeds list later, **then** my draft is still there with whatever data I had typed; I can resume it and add credentials again later if I want.

---

### User Story 3 — Save without enabling (Priority: P3)

A user has finished configuring a feed (all required fields filled in) but isn't ready to turn it on yet. They leave the "Enable feed" checkbox unchecked and click "Save feed". The feed is saved as a draft (because the constrained lifecycle has no `draft → disabled` path). The draft is visible in the feed list with the "Draft" badge. When the user is ready to activate it, they click into the draft, tick "Enable feed", and submit.

**Why this priority**: This is a behavioral detail of the state machine surface. It's worth calling out explicitly so the absence of a `draft → disabled` transition is documented as an intentional choice, not an oversight.

**Independent Test**: Fill in every required field on a new feed but leave "Enable feed" unchecked. Click "Save feed". Verify the feed is saved as a draft (not disabled). Verify the feed list shows the "Draft" badge. Re-open the draft, tick "Enable feed", submit, verify the feed transitions to `enabled`.

**Acceptance Scenarios**:

1. **Given** I'm configuring a new feed with all required fields filled in, **when** I leave "Enable feed" unchecked and click "Save feed", **then** the feed is saved as `draft` (not `disabled`), even though enabled-envelope validation would pass.
2. **Given** I have a draft that meets all the requirements for enabling, **when** I open it and tick "Enable feed", click "Save feed", **then** the feed transitions to `enabled` and source-side fields lock from then on.

### Edge Cases

- **Failed promotion preserves work.** When the user clicks "Save feed" with "Enable feed" checked but an enabled-envelope validation fails (e.g., target group missing), the feed is persisted as a draft with the typed data intact, the form re-renders with errors describing what blocked enabling, and a flash alert states "Saved as draft. Fix the issues below to enable."
- **Failed promotion from a disabled feed.** When the user attempts to re-enable a previously paused feed and validation fails (e.g., the access_token attached to the feed has since been revoked), the feed stays `disabled` (does not silently downgrade to draft — drafts are forward-only, not a fallback for any failed enable). Errors are surfaced in the form.
- **Empty-form save attempt.** The draft envelope still requires `feed_profile_key` and a source-input present (i.e., identification must have completed at least once). If the user somehow submits a form with neither (shouldn't be reachable via UI — the expanded form only renders after identification), the save fails and the user is bounced back to the entry box.
- **Auto-attached credential later deleted.** If the LLM credential auto-attached to a draft is later deleted by the user, the draft's `llm_credential_id` is set to `nil` (existing `LlmCredential` deletion side-effect). The draft remains; it just no longer has a credential attached. The enable check catches this if the user later tries to enable.
- **Auto-attached credential ends up inactive.** Same as the deletion case — the draft retains the (inactive) credential reference; the enable check rejects activation until the credential is replaced or fixed.
- **Source-side editability after pause/resume.** Once a feed transitions out of `draft` for the first time, its source-side fields lock permanently — even if the feed is later paused (`disabled`). Pausing is operational; it doesn't reopen source-side editing. To re-point a feed at a different source, the existing rule applies: start a new feed.
- **Multiple drafts per user.** No cap, no warning. Each draft is its own row. Drafts accumulate in the feed list until manually discarded.

## Requirements *(mandatory)*

### Functional Requirements

**State model**

- **FR-001**: `Feed.state` MUST be an enum with values `draft`, `disabled`, `enabled` (numeric mapping: `draft: 0, disabled: 1, enabled: 2`). New feeds MUST default to `draft`. **Behavioral change**: the default flips from today's `disabled` to `draft`. Both the model `default:` and the schema column `default:` change. Any code, fixture, seed, or `Feed.new` call that relies on "new feeds default to disabled" now defaults to `draft` and MUST be audited. The existing `factories/feeds.rb` factory sets `state` explicitly, so factory-based tests are unaffected; non-factory construction paths (seeds, console scripts, ad hoc test setup) must be reviewed.
- **FR-002**: Allowed state transitions: `draft → enabled` (gated by the enabled envelope), `enabled → disabled` (free, operational), `disabled → enabled` (gated by the enabled envelope). The transitions `draft → disabled` and `enabled → draft` / `disabled → draft` MUST NOT be possible.
- **FR-003**: The `due` scope MUST continue to select only `state: :enabled` feeds. Drafts and paused feeds MUST be excluded from scheduled processing.

**Validation envelopes**

- **FR-004**: The *draft envelope* (validations that apply in any state) MUST consist of: `feed_profile_key` presence and registry inclusion; profile-schema validation of `params`; source-input presence (the profile's `input_shape` key must be present in `params`).
- **FR-005**: The *enabled envelope* (additional validations gated on `enabled?`) MUST consist of: `name` presence; `target_group` presence and format; `access_token` presence and active; `cron_expression` presence and valid syntax; `enabling_requires_recent_preview` (existing rule); `llm_credential` presence and active, **only if** the feed's profile reports `depends_on_ai?`.
- **FR-006**: The `name` validation that today is unconditional MUST be relaxed to apply only when `enabled?`. The draft envelope MUST permit drafts with no name.

**Source-side editability**

- **FR-007**: While `feed.draft?`, the form MUST permit edits to `url`, `feed_profile_key`, and `params`. Changing `url` MUST re-trigger identification.
- **FR-008**: Once a feed has transitioned out of `draft` for the first time, `url`, `feed_profile_key`, and `params` MUST be locked for the remainder of the feed's lifetime, regardless of subsequent pause/resume operations. (Same rule as today's edit-feed behavior in `001-smart-feed-creation` FR-026.)

**Form surface**

- **FR-009**: The expanded feed form MUST present an "Enable feed" checkbox separate from the submit button. The checkbox MUST be always interactable; no client-side disable based on form completeness.
- **FR-010**: The single submit button MUST be labeled "Save feed" regardless of checkbox state. The Stimulus controller that today swaps submit-button labels based on the checkbox MUST be simplified or removed.
- **FR-011**: The checkbox's default checked state on render MUST be: checked if `feed.enabled?`; unchecked otherwise (drafts, paused feeds, new records). On validation-failure re-render, the checkbox state MUST reflect what the user submitted, not the feed's current state.

**Save and promotion flow**

- **FR-012**: On `FeedsController#create` and `#update`, the controller MUST attempt a *single* save at the target state derived from the "Enable feed" checkbox: `:enabled` if checked, otherwise the feed's current state (or `:draft` for a brand-new record). This is important: a two-step "save as draft, then update to enabled" sequence MUST NOT be used, because by the time the second save runs the record is no longer new and the source-side fields are no longer dirty, which causes `enabling_requires_recent_preview` to self-skip and silently turns the preview-token gate into a no-op.
- **FR-013**: When the single save attempt at target state succeeds, the user MUST be redirected per the resulting state (feed show on enable, feeds list on save-as-draft). When the single save attempt FAILS *and* the target state was `:enabled`, the controller MUST:
  1. Capture the enabled-envelope errors collected by the failed save.
  2. Fall back to a fallback state — `:draft` for new records, the prior state (typically `:disabled`) for existing records — and re-save under that state's relaxed envelope so the user's typed data is preserved.
  3. Re-attach the captured enabled-envelope errors to the in-memory feed for display.
  4. Re-render the form with those errors and a flash alert: "Saved as draft. Fix the issues below to enable." for new records, or "Couldn't enable — see issues below." for the re-enable case.

  If the fallback save itself fails (rare — would mean a non-state-specific validation also failed, e.g., a malformed target group), the controller MUST re-render the form with all errors and NOT persist anything.
- **FR-014**: When "Enable feed" is unchecked, the feed MUST be persisted in its current state — drafts stay as drafts, configured feeds (`enabled`) become `disabled`, paused feeds (`disabled`) stay disabled.
- **FR-015**: The credential-gate's "Add AI credentials" button MUST persist the feed under the draft envelope (regardless of "Enable feed" checkbox state) before redirecting to credential setup. This is the only submit path that bypasses the checkbox-driven state decision; in every other case "Save feed" with the checkbox unchecked is the explicit save-as-draft action.

**Credential round-trip**

- **FR-016**: The credential gate in the feed-creation preview pane MUST be a form-submit button (not a navigation link). Clicking it MUST submit the current form with a flag indicating "save as draft and proceed to credential setup."
- **FR-017**: After the credential gate's save-and-redirect, the user MUST land on `new_llm_credential_path(feed_id: <draft id>)`. The `feed_id` parameter MUST carry through the entire credential flow: new → create → show (with polling).
- **FR-018**: `LlmCredentialsController` MUST accept an optional `feed_id` parameter, verify ownership via `current_user.feeds.find_by(id: …)`, and reject (silently ignore, fall back to the credential flow without a return target) any `feed_id` not owned by the current user.
- **FR-019**: When a credential is created via the `feed_id`-aware flow (i.e., the user submitted the credential form with `feed_id` present and authorized), the system MUST auto-attach it to the originating feed at creation time by setting `feed.llm_credential_id = credential.id` — *regardless* of the credential's eventual activation outcome. The user's explicit click on the gate captured the intent "this credential is for this feed"; activation state is enforced separately by the enabled envelope when the user later tries to enable the feed. The auto-attach MUST skip enabled-envelope validations (the feed is in draft; the envelope doesn't apply).
- **FR-020**: When the user is on the LLM credential show page with `feed_id` present *and* the credential has reached `active` state, the credential show partial MUST render a "Continue setting up your feed" button pointing to `edit_feed_path(feed_id)`. (The button MUST NOT appear while the credential is still `pending`/`validating` — auto-attach has happened, but the user benefits from seeing validation succeed before being told to return.)
- **FR-021**: The current `?input=<URL>` plumbing across `LlmCredentialsController`, `LlmCredentials::ValidationsController`, the credential gate, and `Feeds::PreviewsController` MUST be removed entirely. `?feed_id=<id>` replaces it.

**Feed list and discard**

- **FR-022**: The feeds list (`FeedsListComponent` and any related views) MUST visually distinguish drafts from other states. The minimum is a "Draft" badge (and corresponding status icon).
- **FR-023**: Each draft row in the list MUST surface a "Continue setup" affordance (linking to `edit_feed_path(feed)`) and a "Discard" affordance (linking to the destroy action).
- **FR-024**: The destroy action on a draft MUST present a softer confirmation copy than on a configured feed: "Discard this draft? No data will be lost since it hasn't been activated."

**Authorization cleanup (adjacent)**

- **FR-025**: The `llm_credential_belongs_to_user` model validator MUST be removed. Ownership scoping MUST move to the controller seam: `llm_credential_id` and `access_token_id` MUST be looked up via the user's own collection (e.g., `current_user.llm_credentials.find_by(id: …)`) before assignment to a feed.

**Migration impact and audits**

- **FR-026**: The enum numeric remap (`disabled: 0 → 1`, `enabled: 1 → 2`, `draft: 0` new) means any code that references the *literal integer values* of `feeds.state` becomes incorrect on cutover. Such references MUST be found and updated as part of this work. At minimum, audit: raw SQL fragments referencing `feeds.state = <integer>`; ActiveRecord scopes or queries using integers instead of symbols; fixtures; client-side code (Stimulus/JS) that compares against literal integers. Existing example: `FeedsController` (in the sortable status fragment) currently embeds a literal `feeds.state = 1` for "enabled" — that value MUST become `2` (or be rewritten in terms of the symbolic state).

### Key Entities

- **Feed.state** — enum, three values, default `draft`. Encodes the lifecycle. Numeric mapping `{ draft: 0, disabled: 1, enabled: 2 }`. Existing data: the current `disabled: 0, enabled: 1` mapping must be migrated to the new numeric values (data backfill, not just schema change).
- **Feed (validation envelope)** — split into draft envelope (always) and enabled envelope (when `enabled?`). No new columns; relaxed/conditional validators on existing columns.
- **Identification (`FeedIdentification`)** — unchanged. Draft creation does not interact with identification storage.

## Success Criteria *(mandatory)*

- **SC-001**: A user with zero LLM credentials can paste a URL whose profile requires AI, click "Add AI credentials", complete credential setup, return to their draft, finish configuration, and enable the feed — without ever re-typing their original URL or re-doing identification.
- **SC-002**: A user can save a half-configured feed by submitting the form with "Enable feed" unchecked, navigate to /feeds, see the draft listed with a "Draft" badge, click into it, and find all their typed input preserved.
- **SC-003**: A user attempting to enable a draft with missing required fields sees the typed data preserved as a draft, sees plain-language errors describing what's blocking enable, fixes them, resubmits, and successfully enables the feed.
- **SC-004**: A user with multiple drafts sees them all in the feed list with clear distinguishing badges. Each is independently editable and discardable.
- **SC-005**: A user who creates an LLM credential via the gate flow finds the credential auto-attached to the originating draft when they return.

## Assumptions

- The existing identification + preview machinery (introduced in `001-smart-feed-creation`) is in place and functional. This spec does not modify the identification flow itself, only when its results are persisted.
- The existing `LlmCredential` validation polling flow (pending → validating → active/inactive) is in place. This spec extends the polling endpoint to carry `feed_id` but does not change the underlying state machine.
- The existing credential gate UI in `app/views/feeds/_credential_gate.html.erb` is the only location that initiates the AI-credential round-trip from feed creation. (A parallel gate for missing Freefeed access tokens is *not* in scope here.)
- The user's session and ownership model (`current_user.feeds`, `current_user.llm_credentials`) is the canonical scope for ownership checks. Pundit policies already wrap the model layer; ownership scoping in the controller is consistent with how `FeedsController` already builds via `current_user.feeds.build`.

## Dependencies

- `001-smart-feed-creation` provides: the entry point and identification flow; the credential gate UI; the LLM credential resource and polling endpoint; the access token resource.
- No new external dependencies (no new gems, no new third-party services).
- Migration: `feeds.state` numeric remap (existing data uses `0/1` for disabled/enabled; new mapping is `0/1/2` for draft/disabled/enabled). Existing rows whose `state` is `0` must be remapped to `1` (disabled), and rows whose `state` is `1` must be remapped to `2` (enabled). A reversible migration is required.

## Out of scope (for this spec)

- **Drafts for editing existing configured feeds.** This spec covers drafts that arise from the *new-feed creation* flow. The current edit-feed behavior (operational-only edits on configured feeds) is unchanged.
- **A separate `/drafts` URL namespace.** Drafts live at `/feeds/<id>/edit` like every other feed. No new routes.
- **Background expiry / per-user draft cap.** Manual delete only.
- **Auto-save on idle / on field-blur.** The only save triggers are the explicit "Save feed" submit (with the checkbox driving the resulting state) and the credential-gate auto-save.
- **The analogous round-trip for Freefeed access tokens.** When a user has no active access tokens and tries to create a feed, today they hit `feeds/_blocked_no_tokens.html.erb`. Extending the draft round-trip to that gate is a sensible follow-up but is *not* in this spec.
- **Real-time client-side mirroring of the enabled envelope.** The "Enable feed" checkbox is always interactable; whether enabling actually succeeds is decided at submit time on the server, not previewed on the client.
- **A specific "this feed needs setup" notification surface** (in-app or email) beyond the feed list itself. Drafts are visible in the list with a badge; that's the only surface.

## Notes

This spec adds an interruptible *lifecycle* to feeds. It deliberately does not invent new UX vocabulary ("draft" is a state, not a separate model). The form template stays unified between new and edit, with state-aware permits controlling source-side editability and state-aware submit handling controlling the save-and-promote flow. The headline external behavior is: nothing the user has typed is lost when they explicitly save, and the credential dependency is no longer a one-way trip away from their work.
