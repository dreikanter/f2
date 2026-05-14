# Feature Specification: Smart Feed Creation

**Feature Branch**: `001-smart-feed-creation`

**Created**: 2026-05-14

**Status**: Draft

**Input**: User description: "Iterate on the specs in docs/superpowers/specs. Note the latter addition (ability to create new feeds from URL — already implemented manner, or using a prompt, for content sources not available as a RSS/deterministic, procedurally processible source). Focus on simple and clean system design, extensibility, very easy to understand UX (should be accessible to non-technical users). Do not rush to find a solution, analyze, iterate on available approaches, figure out the best system design. Do not make users to keep in mind unnecessary concepts or do unnecessary steps. Prefer to simplify and automate when reasonably possible. Understand the context and the goal well before approaching the solution or planning."

**Parent design**: [`docs/superpowers/specs/2026-05-10-pluggable-profiles-design.md`](../../docs/superpowers/specs/2026-05-10-pluggable-profiles-design.md)
(provides the underlying architecture: pluggable profile registry, three-stage pipeline, LLM credentials, usage tracking)

**Supersedes**: [`docs/superpowers/specs/2026-05-12-profiles-detection-handoff.md`](../../docs/superpowers/specs/2026-05-12-profiles-detection-handoff.md)
(this spec fills the gap that handoff document identified; the handoff doc's open decisions D1–D6 are resolved here under *Assumptions*)

## Why this exists

The most loved property of today's feed creation is that the user pastes one URL and the system does everything else. As Feeder grows to support sources that have no clean machine-readable feed — sites without RSS, social handles, search queries, anything that needs AI to extract — that one-paste experience is at risk: users could be forced to pre-classify their input ("is this a URL or a query?"), pick a "source type" they don't understand, or hit dead ends when nothing matches.

This feature redesigns the feed-creation entry point so it stays a single paste box, recognizes whatever you give it, and gracefully offers AI extraction when no structured feed exists. Users never see the words "profile," "matcher," or "pipeline." They paste, the system shows what it can do, they confirm.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Add an RSS feed by pasting its page URL (Priority: P1)

A user wants to follow a blog. They paste either the blog's homepage URL or its RSS URL. The system finds the feed, fills in a sensible name automatically, and asks only what's truly user-specific: which FreeFeed group to post to, and how often. The user confirms and the feed starts running.

**Why this priority**: This is the existing happy path that today's users rely on. The redesign MUST NOT regress it. If only this story shipped, the feature is no worse than today.

**Independent Test**: Paste the URL of a known-good RSS source. Confirm the system creates the feed without asking the user to choose a "source type" or fill any fields beyond name, group, and schedule. Compare new behavior to current `main`-branch behavior — outputs should match.

**Acceptance Scenarios**:

1. **Given** I'm signed in with a valid FreeFeed access token, **when** I paste a URL that exposes an RSS/Atom feed (directly or discoverable from the page) into the feed entry box and click Continue, **then** the system identifies it, pre-fills the feed name from the source's title, and presents a confirmation step with only the remaining fields editable.
2. **Given** detection has succeeded, **when** I save the feed, **then** the feed begins running on its schedule and publishes posts as in today's behavior.
3. **Given** I paste an XKCD URL, **when** detection runs, **then** the XKCD-specific source type is recognized in preference to generic RSS (current behavior preserved).

---

### User Story 2 — Add a feed from a site that has no RSS, with AI extraction (Priority: P2)

A user pastes the URL of a site they want to follow, but the site doesn't expose an RSS or Atom feed. Instead of seeing "could not identify, try again," the user is offered AI extraction in plain language: "There's no feed here. We can use AI to watch this page and post updates for you." If they accept and have an AI key on file, the feed is created. If they don't have a key, the system explains what to do, helps them add one, and resumes where they left off.

**Why this priority**: This is the headline new capability — making sources without RSS first-class. It also defines the gentle on-ramp for AI features.

**Independent Test**: Paste a URL of a site with no RSS (e.g., a marketing page). Verify the system offers AI extraction, that accepting without a key triggers a guided key-setup flow, and that accepting with a key creates a working feed.

**Acceptance Scenarios**:

1. **Given** I paste a URL whose page has no feed and no special source-type match, **when** detection completes, **then** I see one clear offer to use AI extraction, with a short plain-English explanation of what AI will do, and the cost implication mentioned once.
2. **Given** I accept the AI offer and I have a valid AI key on file, **when** I confirm, **then** the feed is created and begins running.
3. **Given** I accept the AI offer and I do not have a valid AI key, **when** I confirm, **then** the system explains what's needed in plain language, lets me add a key without abandoning the in-progress feed, and returns me to the same confirmation step once the key is saved.
4. **Given** I dismiss the AI offer, **when** I do so, **then** I'm returned to the empty entry box with my original input still visible and editable.

---

### User Story 3 — Add a feed from a handle or search query (Priority: P3)

A user types something that isn't a URL — a handle like `@dhh`, or a phrase like `AI safety news` — into the same paste box. The system recognizes that this isn't a URL and offers one or more ways to follow it (e.g., "Follow `@dhh` on X via AI search," "Follow web search results for `AI safety news`"). Selection works the same as the AI flow in Story 2.

**Why this priority**: Significant expansion of the kinds of sources Feeder can follow, but it depends on Story 2's AI plumbing being in place. Worth shipping as a follow-on once Story 2 lands.

**Independent Test**: Type a handle or a free-text query (not a URL) into the entry box. Verify the system offers sensible AI-backed follow options, and that confirming creates a working feed that produces posts.

**Acceptance Scenarios**:

1. **Given** I enter a recognizable social handle, **when** detection completes, **then** I see at least one AI-backed option to follow that handle, with the source platform indicated.
2. **Given** I enter free-text, **when** detection completes, **then** I see a web-search-based follow option that uses the text as the query.
3. **Given** the input matches multiple plausible follow options, **when** I'm shown the choices, **then** one is marked as recommended and the others are listed below it; non-AI options always rank above AI options for the same input.

---

### User Story 4 — Existing users continue to work without surprise (Priority: P1)

Users who already have feeds created under the old flow keep operating without disruption. Editing an existing feed continues to work; running feeds keep their schedule and don't suddenly require AI keys or new fields they never filled in.

**Why this priority**: Non-regression for the existing tenant base. Same priority tier as Story 1 because failing this is a release-blocker.

**Independent Test**: With a database snapshot containing feeds from the current `main` branch, deploy this feature. Verify all existing feeds still run, that their show/edit pages render, and that nothing in their config has been silently invalidated.

**Acceptance Scenarios**:

1. **Given** a feed was created under the old flow, **when** I view or edit it, **then** all fields are present and editable as before, and no new fields are required.
2. **Given** the system migrates existing feeds, **when** the migration runs, **then** no feed is left in a state that prevents its scheduled run.

---

### Edge Cases

- The user pastes a URL that's reachable but very slow. Detection has a bounded timeout (today: 30 seconds) and a friendly timeout message that lets them retry without losing their input.
- Detection rate limit is hit (today: 10 attempts/min/user). The user sees a calm message ("Give it a moment — too many tries in a row") and an automatic retry countdown, not a generic error.
- The user pastes a URL that detection recognizes, then the source disappears before they confirm. The first scheduled run reports the source error through the standard health surface (existing behavior); the user is not blocked from finishing the form.
- The same source is already followed by the same user. The system flags this at confirmation and offers to open the existing feed instead of creating a duplicate.
- The user pastes a URL that maps to several plausible source types (e.g., a YouTube channel page that also has RSS). The system picks one as recommended (deterministic types beat AI; more specific types beat more generic) and shows the others as alternatives — never as a forced choice.
- The user accepts an AI option, adds a key, but the key fails its validation check. The system blocks save with a clear inline message and a link to the key settings.
- The pasted input is empty or obviously malformed (whitespace only, a single character). The system rejects it before running detection, with a one-line hint.
- The user is in the middle of confirming when their session expires. After re-authenticating, the system returns them to the same confirmation step with their input preserved.

## Requirements *(mandatory)*

### Functional Requirements

**Entry experience**

- **FR-001**: The feed-creation entry point MUST present a single free-form input. It MUST NOT require the user to choose an input type, source type, or category before submitting.
- **FR-002**: The input MUST accept URLs, handles, and free-text. The system MUST classify the input shape internally; the user MUST NOT be asked to declare it.
- **FR-003**: Submission MUST trigger background detection bounded by the existing 30-second timeout and 10-attempts-per-minute rate limit.
- **FR-004**: While detection is in progress, the UI MUST indicate progress and MUST allow the user to cancel without losing their input.

**Detection result handling**

- **FR-005**: Detection MUST return a ranked list of zero or more candidate ways to follow the input. When the list has one entry, the UI MUST behave as today's happy path (auto-fill, light confirmation). When it has more than one, the UI MUST show all options with one marked as recommended. When it has zero, the UI MUST present curated AI-backed fallbacks rather than a hard error.
- **FR-006**: A candidate that depends on AI MUST never be ranked above a candidate that doesn't depend on AI for the same input.
- **FR-007**: Detection MUST NOT call any paid AI service to determine *which* candidates are available. AI-backed candidates MUST be offered based on local rules (input shape, source-side hints) and the AI call MUST be deferred until the user explicitly accepts an AI candidate.

**Confirmation step**

- **FR-008**: The confirmation step MUST auto-fill the feed name from the source's title where available; for inputs without a discoverable title (handles, free-text), the input string MUST be used as the default name. The user MUST be able to edit the name freely.
- **FR-009**: The confirmation form MUST surface only the fields a user must decide: name, FreeFeed group, schedule, plus any input parameters the chosen candidate explicitly declares (e.g., a refinement field for an AI candidate). Internal source-type identifiers MUST NOT be exposed.
- **FR-010**: When the chosen candidate requires an AI key and the user has none on file, the confirmation step MUST guide the user to add a key inline and MUST preserve in-progress feed input across that flow.
- **FR-011**: When the chosen candidate requires an AI key and the user has one on file, no additional steps MUST be required.
- **FR-012**: If detection identifies the same source already followed by this user, the confirmation step MUST warn and offer to open the existing feed instead of creating a duplicate.

**Language and accessibility**

- **FR-013**: User-facing copy MUST avoid implementation vocabulary. The words "profile," "matcher," "pipeline," "stage," "loader," "processor," "normalizer," "LLM" MUST NOT appear in copy shown to end users. "AI" is acceptable; "AI key" is acceptable.
- **FR-014**: When AI is involved, the user MUST be shown, once and briefly, that AI is being used, that it incurs cost they're responsible for, and where to see that cost later.
- **FR-015**: Error and timeout messages MUST be written in plain language and MUST offer a next action, not a dead end.

**Behavior preservation**

- **FR-016**: Feeds created by previous flows MUST continue to run, render, and edit without requiring any new fields, AI keys, or migrations the user must complete manually.
- **FR-017**: The XKCD-over-RSS preference and any other type-specific overrides currently encoded in the matcher chain MUST be preserved in the new candidate ranking.

**Extensibility**

- **FR-018**: Adding a new way to follow content (a new source type, AI-backed or not) MUST require no changes to the feed-creation UI. The new entry MUST slot into the existing registry and surface automatically when its input criteria match.
- **FR-019**: Each registry entry MUST declare which input shapes it accepts (URL, handle, free-text, or any) and what input parameters its confirmation form needs. The form generator MUST render those parameters from the declaration.

### Key Entities

User-facing concepts (these are the only ones a user encounters by name):

- **Feed** — a recurring publication the user owns. They name it, point it at a FreeFeed group, set a schedule.
- **Source** — what the feed follows. Users never categorize sources themselves; the system describes them in human terms ("This site's RSS feed", "AI extraction from this page", "Web search for 'AI safety news'").
- **AI key** — a per-user credential the user adds when they first use an AI-backed source. They see it on a settings page; they manage it like any other credential.

Internal concepts (named here so other artifacts can reference them; not user-visible):

- **Candidate** — one possible way to follow a given input. Detection returns a ranked list of candidates; the UI surfaces them as "options."
- **Profile** (per parent design) — the registry entry that defines a candidate, its accepted input shapes, its parameter schema, and its three-stage execution. Stays in code in v1.
- **Detection** — the process that maps an input to a ranked candidate list. Runs in a background job; never calls the AI provider.

## Success Criteria *(mandatory)*

- **SC-001**: 95% of feeds created during the first month of release reach a working state on the first attempt, measured by "user paste → first successful scheduled run" without re-editing.
- **SC-002**: Median time from paste to confirmed feed (excluding the user's deliberation time during confirmation) is under 10 seconds for inputs that resolve to a single candidate.
- **SC-003**: Zero regressions in current RSS/XKCD feed creation, verified by replaying a representative input set against `main` and the new flow and comparing produced feed configurations.
- **SC-004**: When a user without an AI key accepts an AI-backed candidate, fewer than 10% abandon before adding a key, measured over the first month after Story 2 ships.
- **SC-005**: Zero paid AI provider calls are made during detection itself. Verified by auditing the user-visible AI usage log: detection MUST NOT show up there.
- **SC-006**: Among first-time users observed in usability testing (n ≥ 5), at least 80% can describe what the system did with their input without using the words "profile," "matcher," or "pipeline."
- **SC-007**: For inputs where detection returns multiple candidates, the user picks the recommended one in at least 75% of sessions, indicating the ranking is calibrated.

## Assumptions

These resolve open decisions D1–D6 from the predecessor handoff document; they MAY be revisited during planning but each has a stated rationale.

- **A1 (resolves D1, input surface)**: One free-form input field, not tabs. Rationale: forcing the user to pre-classify their input violates the "no unnecessary concepts" goal. The system, not the user, decides the input shape.
- **A2 (resolves D2, AI probing timing)**: AI detection probing is lazy. AI candidates are advertised based on local rules (input shape, source-side feed absence) and the actual AI call happens only after the user accepts an AI candidate. Rationale: detection runs on every paste; spending tokens to learn "no feed here" would be wasteful and would surprise users with cost.
- **A3 (resolves D3, default feed name)**: Auto-derive from page title where available (existing behavior). For handles and free-text, use the input string as the default name; user can rename. Rationale: keeps the form quiet on the happy path without inventing names the user didn't ask for.
- **A4 (resolves D4, disambiguation placement)**: Disambiguation is inline with the confirmation step — the same page, with the chosen candidate expanding into the parameter form. Rationale: one fewer route, one fewer step, no separate "chooser page" to design and maintain.
- **A5 (resolves D5, input classifier placement)**: The classifier is a planning-time decision; the spec doesn't dictate its location. From the user's perspective, classification is invisible.
- **A6 (resolves D6, detection record schema)**: The detection record schema and any migration path for existing rows are planning-time decisions; this spec requires only that existing feeds continue to function (FR-016).
- **A7**: AI provider in v1 is Anthropic (per parent spec). Users see the brand name once on the key-setup page; elsewhere it's "AI."
- **A8**: Profiles remain code-defined in v1 (per parent spec). End users cannot author their own; operators add new ones via code deployment. Profile authoring by users is future scope.
- **A9**: Cost transparency in v1 is "see your spend after the fact, per feed, on the feed page" (per parent spec phase 4). Hard spending caps are explicitly out of scope (parent spec, future scope).
- **A10**: Detection uses the existing 30-second timeout and 10-attempts-per-minute rate limit (current code). Both are surfaced in friendly language, not as raw error codes.

## Dependencies

- Pluggable profile registry shape (parent spec phase 1) — required for FR-018, FR-019.
- AI credentials model and management UI (parent spec phase 2) — required for FR-010.
- AI client service and the first AI-using profile (parent spec phase 3) — required for Story 2.
- AI loader profiles for handles and free-text (parent spec phase 5) — required for Story 3.

This spec is the user-facing surface that ties those phases together. It SHOULD ship in alignment with phase 3 for Story 1 + Story 2 to be live; Story 3 lights up when phase 5 lands.

## Out of scope (for this spec)

- User-authored profiles (parent spec future scope).
- Spending caps / hard budgets (parent spec future scope, tracked at [#359](https://github.com/dreikanter/f2/issues/359)).
- Bulk import (paste many sources at once).
- Sharing or recommending sources between users.
- Changing an existing feed's source type (parent spec is explicit that profile switching is not supported in v1).
- Mobile-specific layouts; the existing responsive shell is reused.
