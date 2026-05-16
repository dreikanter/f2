# Quickstart: Smart Feed Creation

**Audience**: anyone verifying this feature locally — author, reviewer, QA.
**Plan**: [`plan.md`](./plan.md) · **Spec**: [`spec.md`](./spec.md)

This walkthrough exercises each user story end-to-end against a local dev environment. It assumes the implementation is fully landed; treat it as a definition-of-done checklist.

## 0. Prerequisites

```bash
mise install                           # Ruby and Node per pinned versions
bin/setup                              # Rails install, db:prepare, etc.
bin/rails db:reset                     # fresh DB
bin/rails s                            # Puma on http://localhost:3000
bin/rails solid_queue:start            # background jobs
bin/rails tailwindcss:watch            # CSS rebuild (or `bin/dev` for all of the above)
```

Sign in (or `bin/rails console`-create) a user with at least one **active** FreeFeed access token (existing onboarding flow).

## 1. Story 1 — RSS feed via URL paste (P1)

**Goal**: confirm the today-equivalent happy path still works, with the new ranked-candidate detection contract underneath, and now ends with a preview gate.

1. Navigate to `/feeds/new`.
2. Paste an RSS URL (use `https://daringfireball.net/feeds/main` or a local fixture). Click Continue.
3. **Expect**: polling shell shows progress; within a few seconds, the form expands. The chosen profile is "RSS Feed" (no chooser visible because only one candidate). The feed name is pre-filled with the source's title.
4. **Expect**: a preview pane below the form shows 2–5 recent posts, each with body, optional comments, and any image attachments. The save button label is "Create feed" (not "Save as disabled").
5. Pick a target group, leave the schedule at default. Click Create feed.
6. Redirect to the feed's show page; **confirm** `state = enabled` in the DB or the show-page badge.
7. Wait for the next scheduled run (or trigger via console: `Feed.last.refresh!`); **confirm** posts publish to FreeFeed.

**XKCD specificity check**: repeat steps 1-3 with `https://xkcd.com`. **Expect** the recommended profile is "XKCD" (not "RSS Feed"), even though XKCD is also a valid RSS source.

## 2. Story 2 — AI extraction for a site without RSS (P2)

**Goal**: confirm the AI on-ramp, credentials gate, and preview gating end-to-end.

### 2a. With AI credentials already on file

1. Add an Anthropic credential first: navigate to `/llm_credentials`. Click "New credential". Pick provider Anthropic. Enter a real Anthropic API key. Save → polling shell → settles to `active`.
2. Navigate to `/feeds/new`. Paste a URL that has no RSS feed (e.g. `https://www.anthropic.com`). Click Continue.
3. **Expect**: polling shell → form expands with one candidate, "AI extraction from this page", marked with an AI badge. The cost line is shown once: "AI fetches (including the preview) cost tokens — see your spend on the feed page."
4. **Expect**: preview pane runs the LLM call; within ~30s renders 2–5 sample posts. **Confirm** at the DB level that `LlmUsage` has a new row with `purpose: :preview`, `feed_id: nil`, and a non-zero `cost_estimate_cents`.
5. Click Create feed. Redirect to feed show page; **confirm** `state = enabled`.
6. Trigger a refresh via console (`Feed.last.refresh!`); **confirm** posts published; **confirm** new `LlmUsage` rows with `purpose: :scheduled_run`.

### 2b. Without AI credentials — guided setup

1. As a *different* user with no credentials yet, repeat 2a step 2.
2. **Expect**: same form-expanded state, but accepting the AI candidate at step 4 surfaces an inline credentials-add panel ("To use AI extraction, add an Anthropic API key").
3. Click through to the credential form; add a key; save; settle to `active`. **Expect**: returned to the same confirmation step with the in-progress feed input intact, and the preview now runs.

### 2c. Save anyway after preview failure

1. Add a deliberately-bad Anthropic credential (e.g., a syntactically valid but unauthorized key). Save → settles to `inactive` with a clear error.
2. Use a working credential to start a feed creation that *will* fail at preview time — easiest reproduction: set `Loader::LlmLoader` to use a deliberately-impossible source URL via the form, or stub `LlmClient` in a console test.
3. **Expect**: preview pane shows the failure message and "Save as disabled" button.
4. Click "Save as disabled". **Confirm** feed exists with `state = disabled`.
5. From the feed show page, click "Enable" — **confirm** the system re-runs preview before flipping to `enabled`.

## 3. Story 3 — Handle / search query (P3)

**Goal**: confirm non-URL inputs route to AI-backed profiles.

### 3a. Handle

1. `/feeds/new`. Paste `@dhh`. Click Continue.
2. **Expect**: input classifier identifies as `:handle`; detection returns the AI handle-search profile as the recommended candidate ("Follow `@dhh` on X via AI search"). The candidate chooser shows alternative AI profiles if any matchers fired.
3. Confirm credentials present (or run 2b's guided flow). Preview runs. Save.

### 3b. Free-text query

1. `/feeds/new`. Paste `AI safety news`. Click Continue.
2. **Expect**: input classifier identifies as `:query`; detection returns the AI web-search profile ("Follow web search results for `AI safety news`"). Preview, save, run.

## 4. Reload / refresh behavior (FR-018, FR-019)

**Goal**: confirm in-progress state and preview cache survive reloads without spending tokens.

1. Start an AI-backed feed creation; let preview render.
2. Note the count of `LlmUsage` rows with `purpose: :preview` for your user.
3. Refresh the browser tab (Cmd-R). **Expect**: same form-expanded state, same preview, **same `LlmUsage` count** — no new row.
4. Click "Refresh preview". **Expect**: a new `LlmUsage` row with `purpose: :preview` appears.
5. Change the "AI prompt refinement" parameter (if the profile exposes one). **Expect**: preview auto-re-runs; new `LlmUsage` row.

## 5. Edit feed source (FR-026, FR-027, FR-028)

**Goal**: confirm operational vs source-side edit semantics.

1. Edit an `enabled` RSS feed: change its name and target group, save. **Confirm** state stays `enabled`; no `LlmUsage` rows added; no preview re-run.
2. Edit the same feed: change the URL to a different RSS source. **Expect**: detection re-runs, preview re-runs, save button labelled appropriately. **Confirm** state stays `enabled` after a successful re-preview.
3. Edit an RSS feed: change the URL to one whose detection now matches the *AI website extractor* profile. **Expect**: warning ("This change switches the source type to AI extraction. Past dedup history won't transfer.") with explicit confirm/cancel. On confirm + successful preview, save → state stays `enabled`.

## 6. Multi-credential picker (FR-013)

**Goal**: confirm default-credential behavior.

1. Add a second Anthropic credential ("Work"). On `/llm_credentials`, click "Make default" on it.
2. Start a new AI-backed feed. **Expect**: confirmation step shows a credential picker preselecting "Work".
3. Switch to "Personal" via the picker — **expect**: this changes the feed's credential without changing the user's default. **Confirm** at the DB level that the user's default is still "Work".

## 7. Vocabulary firewall (FR-022)

**Goal**: confirm none of the banned implementation words leak into the UI.

```bash
# From repo root, in your browser, view-source on /feeds/new at each state.
# Or run the specific lint check the team adds during this feature:
bin/rails test test/system/smart_feed_creation_vocabulary_test.rb
```

Banned: "profile", "matcher", "pipeline", "stage", "loader", "processor", "normalizer", "LLM" (any case). Allowed: "AI", "AI credentials", provider brand names.

## 8. Test suite

```bash
bin/rails test
bin/rubocop -f github
```

Both should be green. Migration reversibility:

```bash
bin/rails db:migrate:redo STEP=$(git diff --name-only main... | grep -c db/migrate/)
```

(Roll back and re-apply the new migrations; should round-trip cleanly.)

## 9. Spending visibility (FR-023)

**Goal**: confirm the user can see what AI cost them.

1. Navigate to a feed's show page. **Expect**: an "AI usage" panel showing this feed's lifetime + current-period spend.
2. Navigate to `/settings/llm_usage` (or wherever the parent-spec phase 4 surfaces it). **Expect**: rollup by feed/profile/day; preview-purpose spend separated from scheduled-run spend.

## Done

If every step above passes, the feature meets the spec. Outstanding items:
- Operator-only profile reliability dashboards (parent spec future scope).
- Spending caps (parent spec future scope).
- User-authored profiles (parent spec future scope).
