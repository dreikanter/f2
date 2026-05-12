# Handoff: Detection model evolution for pluggable profiles

**Date:** 2026-05-12
**Status:** Session handoff — pre-spec-kit input
**Parent spec:** [`docs/superpowers/specs/2026-05-10-pluggable-profiles-design.md`](2026-05-10-pluggable-profiles-design.md)
**Branch:** `claude/refine-profiles-design-90zqG`

This document captures the open design problem and the proposal-in-progress from a Claude Code session, formatted to feed into a [spec-kit](https://github.com/github/spec-kit) `/specify` → `/plan` → `/tasks` cycle. Read the parent spec first; this document only describes the gap being closed.

---

## 1. What the parent spec already settles

- Three-stage pipeline (Loader → Processor → Normalizer) stays.
- `FeedProfile` is a code-defined registry; profiles ship with the app.
- LLM stages exist as ordinary stage classes that call a single `LlmClient`.
- New entities: `LlmCredential`, `LlmUsage`. `Feed.params` (JSONB) replaces ad hoc per-profile columns.
- Phased rollout (1–6) is laid out.

## 2. The gap this handoff addresses

The parent spec leaves the **feed-creation UX flow** at the level of "list profiles, select one, fill a generated form" (section: *Feed creation and editing*). That description discards the most valuable property of the current UX, which is:

> On the happy path the user enters **only a URL**. The system detects feed type, extracts the title, and asks the user nothing else. A chooser appears only when detection fails, and is treated as an error state.

Adding LLM-backed profiles breaks this because the input is no longer always a URL — it may be a handle (`@dhh`), a search query (`"AI safety news"`), or a URL of a site with no RSS that needs AI extraction. Detection becomes one-to-many: a single input can map to several plausible profiles.

The spec needs a section that defines **how detection generalizes** without surrendering the URL-first happy path.

## 3. Current baseline (what to preserve)

Verified by reading the code on `main`:

- Entry: `FeedsController#new` renders `feeds/_form_collapsed.html.erb` (single URL field).
- URL → `FeedDetailsController#create` → `FeedDetailsJob` → `FeedDetailsFetcher#identify` (`app/services/feed_details_fetcher.rb:8`).
- Detection: `FeedProfileDetector` (`app/services/feed_profile_detector.rb`) runs matchers in priority order — `ProfileMatcher::XkcdProfileMatcher`, then `ProfileMatcher::RssProfileMatcher`. First hit wins.
- Title auto-fill: `FeedProfile.title_extractor_class_for(profile_key)`.
- Result stored in `FeedDetail`; UI redirects to `feeds/_form_expanded` (URL + profile locked, name editable) on success, or `feeds/_identification_error` ("Try Again" button, no fallback) on failure.
- Registry: `FeedProfile::PROFILES` in `app/models/feed_profile.rb:4-19`, currently `rss` and `xkcd`.

Properties of this UX that must survive the redesign:

1. **One field, one paste, one click** on the happy path.
2. **Detection is the default**; manual choice is the fallback.
3. **No exposed profile-picking** when the system is confident.
4. **Confirmation step exists** but is light: auto-filled fields, user only edits if they want to.

## 4. Proposed conceptual model

### 4.1 Input domain generalizes

`{URL}` → `{URL, handle, free text}`. A cheap, local **input classifier** decides the shape before any network call.

### 4.2 Matcher chain extends

Each registry entry declares the input shape it accepts (`url` | `handle` | `query` | `any`) and a priority. Detection runs the matchers whose shape accepts the classified input, in priority order, and returns a **ranked candidate list** — not a single key.

Hard rule: **an LLM-backed matcher can never outrank a non-LLM matcher on the same input.** If RSS detection succeeds, AI-from-website does not appear as a candidate.

### 4.3 Detection outcome drives three UI paths

- **One confident candidate** → today's happy path (auto-fill, light confirmation). Unchanged for RSS/YouTube/etc.
- **Multiple candidates** → small chooser with a recommended default ("This page has RSS. Or extract with AI instead.").
- **Zero candidates** → curated escape hatch ("I can also follow a topic, a person, or run a custom recipe"), not an error.

The "couldn't identify" error state becomes the **graceful entry point to LLM profiles**: users never see "unsupported source"; they see "no clean feed — extract with AI?"

### 4.4 Lazy LLM probing

The AI-from-website matcher *reports availability* without calling the LLM. The actual extraction call is deferred until the user opts in. Detection must not spend Claude tokens on every failed URL.

### 4.5 LLM-credential gate

The existing access-token gate pattern (`/feeds/new`) is mirrored: only triggers *after* the user accepts an AI candidate. Users without credentials can still browse the candidate list and learn what's possible.

## 5. Five-input walk-through

| Input | Today | Proposed |
|---|---|---|
| `https://blog.example.com/feed.xml` | RSS, auto-name | unchanged |
| `https://www.youtube.com/@person` | (planned) YouTube | unchanged |
| `https://someblog.com` (no RSS) | hard error, "Try Again" | "No feed here. Extract with AI?" (lazy probe) |
| `@dhh` | rejected as invalid URL | "Follow @dhh on X via AI search?" |
| `AI safety news` | rejected | "Follow web search for 'AI safety news'?" |

## 6. Concrete spec additions needed

These are the edits to fold into `2026-05-10-pluggable-profiles-design.md`:

1. **Registry shape**: add `input_shape` and `input_matcher` fields to each `FeedProfile` entry; document the LLM-cannot-outrank-non-LLM rule.
2. **Detection contract**: change return type from "profile_key or null" to "ranked candidate list with one recommended candidate." `FeedDetail` grows to persist the candidate list so the confirmation UI can offer alternatives.
3. **New section** under *User-facing surfaces* describing the three UI paths from §4.3 above, replacing the current "lists profiles, select one" wording.
4. **Phase ordering note**: detection generalization is a prerequisite for any phase that ships a user-visible LLM profile (phase 3 onwards). It may need to land in phase 2 or as a phase 2.5.

## 7. Open decisions (for `/specify` clarification)

These are deliberate forks the next session needs to resolve before planning:

- **D1. One box vs. tabs.** Single input ("paste anything") is smoother but more mysterious; tabbed entry ("URL | Topic | Custom") is clearer but reintroduces an up-front choice. Current recommendation: **one box**, teach via placeholder + candidate list.
- **D2. Lazy vs. eager AI probing.** Recommended: lazy (don't burn tokens on failed URL detection). Confirm.
- **D3. Default `feed.name` for free-text inputs.** Use the input string itself? LLM-generated label? Recommended: input string with optional later rename.
- **D4. Disambiguation surface.** Is the multi-candidate chooser the *same* page as the confirmation form (inline) or a step before it? Affects controller routing and `FeedDetail` lifecycle.
- **D5. Where input classification lives.** A new `InputClassifier` service, or a method on `FeedProfileDetector`? Recommended: separate service — keeps detector's "run matchers" responsibility clean.
- **D6. Backward-compat with `FeedDetail`.** Existing rows have a single `feed_profile_key`. Migrate to a candidate-list column or keep `feed_profile_key` as "the recommended one" and add a sibling column? Recommended: latter, smaller diff.

## 8. Constraints worth restating

- Profiles are **code, not data**, in v1 — adding "AI from website" is a registry entry plus a stage class, not a DB migration.
- The pipeline shape (Loader/Processor/Normalizer) does not change.
- Detection runs in a background job today (`FeedDetailsJob`); that stays.
- Rate limit: 10 detection attempts/min/user (`feed_details_controller.rb:6`).
- 30s timeout on detection (`feed_details_controller.rb:4`).

## 9. Suggested spec-kit kickoff

```
/specify Generalize feed-creation detection to handle URLs, handles, and free-text
queries, returning a ranked candidate list. Preserve the one-paste happy path for
RSS/YouTube. Use the "couldn't identify" state as the graceful entry point to
LLM-backed profiles. See docs/superpowers/specs/2026-05-12-profiles-detection-handoff.md
for full context, baseline code references, and open decisions D1–D6.
```

After `/specify` produces a feature spec, run `/plan` against this branch
(`claude/refine-profiles-design-90zqG`). The parent design doc
(`2026-05-10-pluggable-profiles-design.md`) is the long-term contract; this
detection work is a sub-spec that should reference back to it.

## 10. Files to read first in the next session

- `docs/superpowers/specs/2026-05-10-pluggable-profiles-design.md` (parent spec)
- `app/models/feed_profile.rb` (registry shape today)
- `app/services/feed_profile_detector.rb` (matcher chain)
- `app/services/feed_details_fetcher.rb` (orchestration)
- `app/controllers/feed_details_controller.rb` (UI-facing flow)
- `app/views/feeds/_form_collapsed.html.erb`, `_form_expanded.html.erb`, `_identification_error.html.erb` (current UX)
