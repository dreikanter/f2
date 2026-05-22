# Feature Specification: Smart Feed Creation

**Created**: 2026-05-14

**Status**: Draft

**Input**: User description: "Iterate on the specs in docs/superpowers/specs. Note the latter addition (ability to create new feeds from URL — already implemented manner, or using a prompt, for content sources not available as a RSS/deterministic, procedurally processible source). Focus on simple and clean system design, extensibility, very easy to understand UX (should be accessible to non-technical users). Do not rush to find a solution, analyze, iterate on available approaches, figure out the best system design. Do not make users to keep in mind unnecessary concepts or do unnecessary steps. Prefer to simplify and automate when reasonably possible. Understand the context and the goal well before approaching the solution or planning."

**Parent design**: pluggable profile architecture — three-stage pipeline (Detector / Fetcher / Normalizer), profile registry, LLM credentials, usage tracking. Originally drafted in `docs/superpowers/specs/2026-05-10-pluggable-profiles-design.md` (since removed); the architecture it described is the foundation this spec builds on.

**Supersedes**: the earlier handoff doc `docs/superpowers/specs/2026-05-12-profiles-detection-handoff.md` (since removed). Its open decisions D1–D6 are resolved here under *Assumptions*.

## Clarifications

### Session 2026-05-15

- Q: When a user saves a feed before preview validation passes (e.g., "save anyway" after preview failure, or saving without a successful preview), what state is the feed saved in? → A: Disabled (the existing model default); only a successful preview can gate saving in enabled state.
- Q: When a user has multiple acceptable AI credentials, how does the confirmation step preselect one? → A: The credential model gets an explicit per-provider `default` flag with a "Make default" affordance on the credentials settings page; the picker preselects the user's default for the required provider; the user can override per feed.
- Q: How does editing an existing feed integrate with detection + preview? → A: Operational fields (name, target group, schedule, credential reference) edit freely with no validation. Source-side fields (URL/handle/query/profile parameters) re-trigger detection + preview on change and re-gate `enabled` state via FR-016 (saving without a green preview transitions the feed to `disabled`). If detection on the edited input would match a different profile than the current one, the system warns and asks the user to confirm (since prior dedup history applies to the old profile/source combination); profile *switching* via edit otherwise follows the same rules as new-feed creation.
- Q: When a user reloads or revisits an in-progress confirmation step, do detection and preview re-run? → A: Detection results persist for the lifetime of the in-progress flow; reloads/navigation restore them without re-running. Preview auto-re-runs only when the user changes a source-side field; otherwise the previously rendered preview is shown from cache. An explicit "Refresh preview" control is always available so the user can spend AI tokens deliberately.
- Q: How does duplicate-feed detection work — i.e., what happens when the user creates a second feed pointing at a source they're already following? → A: It doesn't exist. The earlier "warn on same source" requirement is removed. Following the same source twice is a legitimate use case (e.g., reposting the same content to two different FreeFeed groups). The system MUST NOT prevent or warn about it.

## Why this exists

The most loved property of today's feed creation is that the user pastes one URL and the system does everything else. As Feeder grows to support sources that have no clean machine-readable feed — sites without RSS, social handles, search queries, anything that needs AI to extract — that one-paste experience is at risk: users could be forced to pre-classify their input ("is this a URL or a query?"), pick a "source type" they don't understand, or hit dead ends when nothing matches.

This feature redesigns the feed-creation entry point so it stays a single paste box, recognizes whatever you give it, and gracefully offers AI extraction when no structured feed exists. Users never see the words "profile," "matcher," or "pipeline." They paste, the system shows what it can do, they confirm.

## User Scenarios & Testing *(mandatory)*

### User Story 1 — Add an RSS feed by pasting its page URL (Priority: P1)

A user wants to follow a blog. They paste either the blog's homepage URL or its RSS URL. The system finds the feed, fills in a sensible name automatically, and asks only what's truly user-specific: which FreeFeed group to post to, and how often. The user confirms and the feed starts running.

**Why this priority**: RSS is the dominant content-source format and the smallest viable slice of the feature. Story 1 alone gives users a working feed-creation flow; everything else extends it.

**Independent Test**: Paste the URL of a known-good RSS source. Confirm the system creates the feed without asking the user to choose a "source type" or fill any fields beyond name, group, and schedule, and that the feed produces posts on its scheduled runs.

**Acceptance Scenarios**:

1. **Given** I'm signed in with a valid FreeFeed access token, **when** I paste a URL that exposes an RSS/Atom feed (directly or discoverable from the page) into the feed entry box and click Continue, **then** the system identifies it, pre-fills the feed name from the source's title, and presents a confirmation step with only the remaining fields editable alongside a preview of 2 to 5 recent posts in their would-be-published form.
2. **Given** I'm reviewing the confirmation step, **when** the preview shows recent posts that look like what I expect (body, optional supplementary content, attached images, link back to the source), **then** I save the feed and it begins running on its schedule.
3. **Given** I paste an XKCD URL, **when** detection runs, **then** the XKCD-specific source type is recognized in preference to generic RSS, because more specific source types outrank generic ones; the preview shows recent XKCD entries.

---

### User Story 2 — Add a feed from a site that has no RSS, with AI extraction (Priority: P2)

A user pastes the URL of a site they want to follow, but the site doesn't expose an RSS or Atom feed. Instead of seeing "could not identify, try again," the user is offered AI extraction in plain language: "There's no feed here. We can use AI to watch this page and post updates for you." If they accept and have AI credentials on file, the feed is created. If they don't, the system explains what to do, helps them add credentials, and resumes where they left off.

**Why this priority**: This is the headline new capability — making sources without RSS first-class. It also defines the gentle on-ramp for AI features.

**Independent Test**: Paste a URL of a site with no RSS (e.g., a marketing page). Verify the system offers AI extraction, that accepting without AI credentials triggers a guided credential-setup flow, and that accepting with credentials on file creates a working feed.

**Acceptance Scenarios**:

1. **Given** I paste a URL whose page has no feed and no special source-type match, **when** detection completes, **then** I see one clear offer to use AI extraction, with a short plain-English explanation of what AI will do, and the cost implication mentioned once (including that the preview itself costs AI tokens).
2. **Given** I accept the AI offer and I have valid AI credentials on file, **when** the system fetches a sample using my credentials, **then** I see a preview of 2 to 5 posts in the same structural form they'd take on FreeFeed; on confirming I save the feed and it begins running.
3. **Given** I accept the AI offer and I have no valid AI credentials, **when** I confirm, **then** the system explains what's needed in plain language, lets me add credentials without abandoning the in-progress feed, and returns me to the same confirmation step (where the preview then runs) once credentials are saved.
4. **Given** the preview's AI fetch fails or returns unparseable output, **when** I see the failure message, **then** I can retry the preview, accept the risk and save anyway, or back out.
5. **Given** I dismiss the AI offer, **when** I do so, **then** I'm returned to the empty entry box with my original input still visible and editable.

---

### User Story 3 — Add a feed from a handle or search query (Priority: P3)

A user types something that isn't a URL — a handle like `@username`, or a phrase like `AI safety news` — into the same paste box. The system recognizes that this isn't a URL and offers one or more ways to follow it (e.g., "Follow `@username` on X via AI search," "Follow web search results for `AI safety news`"). Selection works the same as the AI flow in Story 2.

**Why this priority**: Significant expansion of the kinds of sources Feeder can follow, but it depends on Story 2's AI plumbing being in place. Worth shipping as a follow-on once Story 2 lands.

**Independent Test**: Type a handle or a free-text query (not a URL) into the entry box. Verify the system offers sensible AI-backed follow options, and that confirming creates a working feed that produces posts.

**Acceptance Scenarios**:

1. **Given** I enter a recognizable social handle, **when** detection completes, **then** I see at least one AI-backed option to follow that handle, with the source platform indicated.
2. **Given** I enter free-text, **when** detection completes, **then** I see a web-search-based follow option that uses the text as the query.
3. **Given** the input matches multiple plausible follow options, **when** I'm shown the choices, **then** one is marked as recommended and the others are listed below it; non-AI options always rank above AI options for the same input.

---

### Edge Cases

- The user pastes a URL that's reachable but very slow. Detection has a bounded timeout (today: 30 seconds) and a friendly timeout message that lets them retry without losing their input.
- Detection rate limit is hit (today: 10 attempts/min/user). The user sees a calm message ("Give it a moment — too many tries in a row") and an automatic retry countdown, not a generic error.
- The user pastes a URL that detection recognizes, then the source disappears before they confirm. The user is not blocked from finishing the form; the first failed scheduled run is reported through the standard feed-health surface.
- The user pastes a URL that maps to several plausible source types (e.g., a YouTube channel page that also has RSS). The system picks one as recommended (deterministic types beat AI; more specific types beat more generic) and shows the others as alternatives — never as a forced choice.
- The user accepts an AI option, adds credentials, but they fail the provider's validation check. The system blocks save with a clear inline message and a link to the credentials settings.
- Preview returns zero posts because the source is brand new or temporarily empty. The system says "no recent posts to preview yet" and lets the user save anyway; the feed will pick up posts when they appear.
- Preview generation takes longer than expected (slow source, slow AI call). The UI shows progress and a friendly "this can take a moment" hint instead of a spinner with no context.
- The pasted input is empty or obviously malformed (whitespace only, a single character). The system rejects it before running detection, with a one-line hint.
- The user is in the middle of confirming when their session expires. After re-authenticating, the system returns them to the same confirmation step with their input preserved.

## Requirements *(mandatory)*

### Functional Requirements

**Entry experience**

- **FR-001**: The feed-creation entry point MUST present a single free-form input. It MUST NOT require the user to choose an input type, source type, or category before submitting.
- **FR-002**: The input MUST accept URLs, handles, and free-text. The system MUST classify the input shape internally; the user MUST NOT be asked to declare it.
- **FR-003**: Submission MUST trigger background detection bounded by a 30-second timeout and a 10-attempts-per-minute per-user rate limit.
- **FR-004**: While detection is in progress, the UI MUST indicate progress and MUST allow the user to cancel without losing their input.

**Detection result handling**

- **FR-005**: Detection MUST return a ranked list of zero or more profiles that match the input. When the list has one entry, the UI MUST auto-fill and present a light confirmation step (no chooser). When it has more than one, the UI MUST show all options with one marked as recommended. When it has zero, the UI MUST present curated AI-backed fallbacks rather than a hard error.
- **FR-006**: An AI-backed profile MUST never be ranked above a non-AI profile for the same input.
- **FR-007**: Detection MUST NOT call any paid AI service to determine *which* profiles match. AI-backed profiles MUST be offered based on local rules (input shape, source-side hints), and the AI call MUST be deferred until the user explicitly picks an AI-backed option.

**Confirmation step**

- **FR-008**: The confirmation step MUST auto-fill the feed name from the source's title where available; for inputs without a discoverable title (handles, free-text), the input string MUST be used as the default name. The user MUST be able to edit the name freely.
- **FR-009**: The confirmation form MUST surface only the fields a user must decide: name, FreeFeed group, schedule, plus any input parameters the chosen profile explicitly declares (e.g., a refinement field for an AI-backed profile). Internal source-type identifiers MUST NOT be exposed.
- **FR-010**: When the chosen profile requires AI credentials and the user has none on file for an acceptable provider, the confirmation step MUST guide the user to add credentials inline and MUST preserve in-progress feed input across that flow.
- **FR-011**: When the chosen profile requires AI credentials and the user already has acceptable credentials on file, no additional steps MUST be required.
- **FR-012**: AI credentials MUST be managed as a standalone resource in a dedicated settings area (list, add, validate, revoke), mirroring how FreeFeed access tokens are managed today. The smart feed-creation flow MUST NOT define an alternative credential-storage path; the "add credentials inline" experience in FR-010 surfaces the same credential-management view, not a parallel one.
- **FR-013**: A feed that runs an AI-backed profile MUST reference the credential it will use at run time. The credential model MUST carry an explicit per-provider `default` flag (managed on the credentials settings page via a "Make default" affordance, with the constraint that at most one credential per provider per user is the default). The confirmation step's picker MUST preselect the user's default credential for the required provider, MUST be hidden when only one acceptable credential exists, and MUST allow the user to override the selection per feed without changing the default.
**Preview**

- **FR-014**: After detection succeeds and any required credentials are in place, the confirmation step MUST attempt to fetch a sample of recent posts from the source and present them as a preview alongside the form. Target sample size: 2 to 5 posts.
- **FR-015**: Preview posts MUST be rendered in the structural form they will take when published to FreeFeed — at minimum: post body, optional comments for supplementary or overflow content (e.g., long-form material that doesn't fit the body, or the original content when the post body is a summary), and attached images. Pixel-perfect visual fidelity to FreeFeed's rendering is explicitly out of scope for early revisions.
- **FR-016**: The preview is the user's confirmation that the feed is interpreted correctly and is the sole gate to saving a feed in the `enabled` state. Saving with a successful preview MUST create the feed in `enabled` state; saving without one (failure, dismissed, never run) MUST create the feed in the existing default `disabled` state. The save action MUST be co-located with the preview so saving means "this is roughly what will be published."
- **FR-017**: If preview generation fails (source unreachable, no posts available yet, AI returns unparseable output, etc.), the system MUST surface a plain-language explanation, MUST allow the user to retry, and MUST allow the user to save the feed as `disabled` if they choose. The save button in this case MUST clearly label the outcome ("Save as disabled" or equivalent) so the user knows the feed won't run until they enable it from its show/edit page. Preview failure MUST NOT silently fall back to a blank state.
- **FR-018**: Detection results MUST persist for the lifetime of the in-progress feed-creation (or feed-edit) flow. Reloads of the confirmation page, navigation away and back, or session resumption MUST restore the cached detection result without re-running detection.
- **FR-019**: Preview MUST auto-re-run only when the user changes a source-side field. Page reloads, idle returns, navigation back to the confirmation step, and session resumption MUST serve the previously rendered preview from cache. The preview area MUST include an explicit "Refresh preview" control so the user can spend AI tokens deliberately.

**Profile output contracts (user-facing aspect)**

- **FR-020**: All profiles, AI-backed or not, MUST produce posts of a single structural shape (post body, optional supplementary content, images, source URL, publication date). The user MUST NOT be asked to define output fields, schemas, templates, or field maps; structure is a property of the profile, not of the feed.
- **FR-021**: The system MUST prevent the same source post from being republished within a single feed across scheduled runs. The user MUST NOT be asked to configure dedup keys, identifiers, or matching rules; the profile is responsible for deriving a stable per-post identifier.

**Language and accessibility**

- **FR-022**: User-facing copy MUST avoid implementation vocabulary. The words "profile," "matcher," "pipeline," "stage," "loader," "processor," "normalizer," "LLM" MUST NOT appear in copy shown to end users. "AI," "AI credentials," and provider brand names (e.g., "Anthropic API key") are acceptable.
- **FR-023**: When AI is involved, the user MUST be shown, once and briefly, that AI is being used, that AI fetches (including the preview) incur cost they're responsible for, and where to see that cost later.
- **FR-024**: Error and timeout messages MUST be written in plain language and MUST offer a next action, not a dead end.

**Ranking rules**

- **FR-025**: For the same input, a more specific source type MUST outrank a more generic one (e.g., an XKCD-aware source type outranks generic RSS).

**Edit feed**

- **FR-026**: Editing an existing feed MUST allow operational fields (name, target group, schedule, AI credential reference) to be changed freely. These edits MUST NOT trigger detection or preview, and MUST NOT change the feed's `state`.
- **FR-027**: Editing source-side fields (the original input the feed was created from, plus any profile parameters) MUST re-trigger detection and preview. The save action MUST re-apply FR-016: a successful new preview is required to save the feed in `enabled` state; otherwise the save transitions the feed to `disabled`.
- **FR-028**: When detection on the edited source-side input matches a *different* profile than the feed's current one, the system MUST warn the user that prior dedup history applies to the old profile/source pairing and MUST require explicit confirmation before saving. No automatic profile switch may occur silently.

**Extensibility**

- **FR-029**: Adding a new way to follow content (a new source type, AI-backed or not) MUST require no changes to the feed-creation UI. The new entry MUST slot into the existing registry and surface automatically when its input criteria match.
- **FR-030**: Each registry entry MUST declare which input shapes it accepts (URL, handle, free-text, or any) and what input parameters its confirmation form needs. The form generator MUST render those parameters from the declaration.
- **FR-031**: Adding a new AI provider MUST be possible without changes to the feed-creation UI or to any non-AI source type. The credential model MUST treat the provider as a variable and the provider-specific field set as data the credential form is generated from.

### Key Entities

User-facing concepts (these are the only ones a user encounters by name):

- **Feed** — a recurring publication the user owns. They name it, point it at a FreeFeed group, set a schedule.
- **Source** — what the feed follows. Users never categorize sources themselves; the system describes them in human terms ("This site's RSS feed", "AI extraction from this page", "Web search for 'AI safety news'").
- **AI provider credentials** — a per-user record that lets the application call an AI service on the user's behalf. Modeled in parallel with FreeFeed access tokens: managed as a standalone resource in a dedicated settings area, listed/added/validated/revoked there, and *referenced* by a feed at run time (the way a feed references its access token for publishing). The credential record carries:
  - A **provider reference** (Anthropic, OpenAI, an OpenAI-compatible endpoint, etc.).
  - **Provider-specific credential fields** — an API key, an API key + organization ID, an API key + base URL for self-hosted endpoints, OAuth-style token sets, or whatever the chosen provider requires. Different providers contribute different field sets; the data model MUST treat the provider as a variable and the credential fields as provider-specific so that adding a new provider is a registry/migration change, not a redesign.
  - A user-supplied **display name** for distinguishing multiple credentials (e.g., "Personal," "Work").
  - A **default** flag (per-provider, per-user; at most one default per provider). The credentials settings page exposes a "Make default" affordance. The default is what the feed-creation picker preselects.
  - Validation state and the usual timestamps.

  A user MAY have zero or more credentials, across one or more providers. When an AI-backed profile is selected for a feed, the feed references the credential it will use — explicitly chosen if more than one acceptable credential exists, otherwise implicit. The casual UI label adapts to the provider ("Anthropic API key," "OpenAI key," etc.); on a multi-provider settings page they sit together as "AI providers."

Internal concepts (named here so other artifacts can reference them; not user-visible):

- **Profile** (per parent design) — the registry entry that defines a way to follow content: which input shapes it accepts, how it matches an input, the parameters it asks for, and its three-stage execution. Stays in code in v1.
- **Detection** — the process that matches a user input against the profile registry and returns the matching profiles in ranked order. Runs in a background job; never calls the AI provider. The UI surfaces matching profiles to the user as "options."

## Success Criteria *(mandatory)*

- **SC-001**: 95% of feeds created during the first month of release reach a working state on the first attempt, measured by "user paste → first successful scheduled run" without re-editing.
- **SC-002**: Median time from paste to confirmed feed (excluding the user's deliberation time during confirmation) is under 10 seconds for inputs that resolve to a single matching profile.
- **SC-003**: When a user without AI credentials picks an AI-backed option, fewer than 10% abandon before adding credentials, measured over the first month after Story 2 ships.
- **SC-004**: Zero paid AI provider calls are made during detection itself. Verified by auditing the user-visible AI usage log: detection MUST NOT show up there.
- **SC-005**: Among first-time users observed in usability testing (n ≥ 5), at least 80% can describe what the system did with their input without using the words "profile," "matcher," or "pipeline."
- **SC-006**: For inputs where detection returns multiple matching profiles, the user picks the recommended one in at least 75% of sessions, indicating the ranking is calibrated.
- **SC-007**: Across feeds created, fewer than 5% are deleted by their owner within 7 days of creation, indicating the preview adequately confirms the feed's behavior before save.
- **SC-008**: Zero duplicate posts published within the same feed across scheduled runs, measured per feed across a representative one-month window.

## Assumptions

These resolve open decisions D1–D6 from the predecessor handoff document; they MAY be revisited during planning but each has a stated rationale.

- **A1 (resolves D1, input surface)**: One free-form input field, not tabs. Rationale: forcing the user to pre-classify their input violates the "no unnecessary concepts" goal. The system, not the user, decides the input shape.
- **A2 (resolves D2, AI probing timing)**: AI detection probing is lazy. AI-backed profiles are advertised based on local rules (input shape, source-side feed absence); the actual AI call happens only after the user picks one. Rationale: detection runs on every paste; spending tokens to learn "no feed here" would be wasteful and would surprise users with cost.
- **A3 (resolves D3, default feed name)**: Auto-derive from page title where available. For handles and free-text, use the input string as the default name; user can rename. Rationale: keeps the form quiet on the happy path without inventing names the user didn't ask for.
- **A4 (resolves D4, disambiguation placement)**: Disambiguation is inline with the confirmation step — the same page, with the chosen profile expanding into the parameter form. Rationale: one fewer route, one fewer step, no separate "chooser page" to design and maintain.
- **A5 (resolves D5, input classifier placement)**: The classifier is a planning-time decision; the spec doesn't dictate its location. From the user's perspective, classification is invisible.
- **A6 (resolves D6, detection record schema)**: The detection record schema is a planning-time decision. The app has no production users yet, so any required data-shape changes ship without a migration story.
- **A7**: The first AI provider shipped is Anthropic (per parent spec phase 3). The credential model is provider-agnostic from day one (FR-020), so adding a second provider later is a registry/migration change with no rework of the feed-creation UI. Users see the provider's brand name on the credentials settings page and wherever a specific credential is named or selected; elsewhere the casual label is just "AI."
- **A8**: Profiles remain code-defined in v1 (per parent spec). End users cannot author their own; operators add new ones via code deployment. Profile authoring by users is future scope.
- **A9**: Cost transparency in v1 is "see your spend after the fact, per feed, on the feed page" (per parent spec phase 4). Hard spending caps are explicitly out of scope (parent spec, future scope).
- **A10**: Detection uses a 30-second timeout and a 10-attempts-per-minute per-user rate limit. Both are surfaced in friendly language, not as raw error codes. Numbers can be tuned during planning if a better default emerges.

## Dependencies

- Pluggable profile registry shape (parent spec phase 1) — required for FR-029, FR-030.
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
- Mobile-specific layouts beyond what the standard responsive shell delivers.
