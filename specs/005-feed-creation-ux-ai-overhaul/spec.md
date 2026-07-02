# Feed Creation UX + AI Architecture Overhaul

**Date**: 2026-06-29 | **Status**: Design (pre-implementation)

**Related**: [`001-smart-feed-creation`](../001-smart-feed-creation/spec.md) (the flow this revises),
[`002-feed-drafts`](../002-feed-drafts/spec.md), [`003-unify-feed-preview-stack`](../003-unify-feed-preview-stack/spec.md),
[`004-manual-feed-preview`](../004-manual-feed-preview/spec.md) · PRs: #873 (per-feed provider/model), #877 (capability matrix, WIP)

This is the design/rationale record for a set of related changes to feed creation UX and the
AI (LLM) stack. It may ship across multiple PRs. Where the code later diverges, the code is the
source of truth; this document records *why* the decisions were made.

## Why

Several gaps surfaced while revisiting the `001-smart-feed-creation` decisions:

- The single smart-input field + shape auto-detection conflates two genuinely different things
  (a URL vs a prompt) and hides the AI capability behind an ambiguous box.
- "Feed type" is surfaced as a concept the user shouldn't have to reason about; for prompt feeds
  it's meaningless.
- The two AI profiles (`llm_website_extractor`, `llm_web_search`) are the same machinery with
  different prompts/tools — redundant.
- Source/profile editing is locked after a feed leaves draft; this is over-restrictive, and
  especially painful for AI feeds where the prompt *is* the source.
- The LLM stack leaks "how we talk to a provider" (structured output, web access) into the feed
  profile instead of behind a thin per-provider seam, and the current `with_tool("web_search")`
  call is a no-op misuse (RubyLLM `with_tool` is for function tools, not server tools).
- Preview is *believed* to gate enabling, but the code already does not gate on it.

## Core mental model

The user picks an **engine** (mechanism), not an input syntax. Two modes:

| | Mode A — "Follow a feed or channel" | Mode B — "Follow with AI" |
|---|---|---|
| Engine | Deterministic profiles (RSS, YouTube, Reddit, …) | Single AI profile (LLM + web access) |
| Input | A URL (single-line **"Source link"** field) | Free-form **"What should AI follow?"** textarea |
| Accepts | A link (scheme auto-fixed) | A link, several links, or a description |

The **mode toggle** carries the mechanism; the **field label** carries the expected input type.
There is no auto-detection of input *shape* — the user stays in the engine they chose — but each
field *validates* form within its mode. A URL pasted into Mode B is fine (AI reads it); a non-URL
in Mode A is routed to Mode B via an inline bridge.

## Decisions

### 1. Entry & modes

- **Two explicit modes by mechanism**, labelled "Follow a feed or channel" / "Follow with AI".
  Drop shape auto-detection.
- **Two label slots, each with one job**: mode toggle = mechanism; field label = input type
  ("Source link" / "What should AI follow?"). Never overload one with both — that was the
  category error in the old single box.
- Mode A field: single-line URL input. **Silent scheme-fix** (`example.com` → `https://example.com`);
  **respect an explicit `http://`** (never force https — some feeds are http-only);
  **no shorthand expansion** (`r/x`, `@handle` are *not* expanded — ambiguous handles can't be
  resolved deterministically and the AI bridge handles them better).
- **Mode A has exactly two failure exits, and they are the same exit**: input isn't a URL
  (client-side, before any fetch) or is a URL but yields no feed (after detection). Both route to
  the same **"Follow with AI instead"** bridge, carrying the input into Mode B.

### 2. AI feed model

- **Collapse the two AI profiles into one** (`input_shape: :any`). Web access is intrinsic to the
  AI engine, not a per-profile toggle, so it leaves the profile config.
- **One free-form prompt** captures *both* what to follow and how to transform it
  (e.g. "Follow A24's blog and turn each new post into a one-line announcement"). The
  source/transformation boundary is genuinely fuzzy for AI feeds; forcing a structured
  source+instructions split adds friction without clarity.
- A **system prompt wraps** the user prompt and owns: the goal (aggregate web content per the user
  prompt), the structured-output schema, the uid contract (§3), the standing-query-vs-feed-style
  regime distinction (§3), and the safeguards (§8). The user prompt is data inside this frame.

### 3. uid contract (integrity)

The uid is the one place an AI feed can quietly corrupt itself (duplicate or dropped reposts).

- **uid is anchored to source identity, not generated content.** Content-hash uids are fatal here
  because AI feeds may *summarize/reshape* content — the body changes every run. The default is
  **`normalize(permalink)`**: lowercase host, strip `utm_*`/fragments, canonicalize trailing slash.
- **The model never mints the uid string.** It only *signals the regime* per item: a real permalink
  (feed-style → dedup) or a null permalink + period hint (standing-query/digest). The **processor**
  mints the actual uid string using a trustworthy server clock — the model has no reliable clock and
  must not stamp dates.
- **Standing query / digest is first-class** (e.g. "is AGI achieved yet?", asked daily). It emerges
  from the permalink rule: no permalink → processor mints a **period-keyed** uid (default = run date)
  → one fresh post per period. A standing query yields exactly one synthesized item per run.
- **Placement is load-bearing.** `filter_new_entries` (dedup) and the blank-uid drop both run *after*
  `process_feed_contents`, so the uid must be final by the end of that step. uid minting therefore
  lives in `PassthroughProcessor` (mirroring `RssProcessor#extract_uid`), delegating policy to a
  new, unit-tested, clock-injected `Uid::Resolver`. Minting it any later would let the existing
  guards drop digest items.

### 4. Editing & lifecycle

- **Unlock** source/profile/prompt editing after draft (controller strong-params + the disabled
  form fields in `_form_expanded.html.erb`).
- **`import_after` is the single user-owned backlog lever**, not a dedup mechanism. No silent
  baseline reseed — a reseed can't match revision-2 items against revision-1 items, so it would
  silently swallow transition-window posts (a worse, invisible failure than the duplicates it
  prevents).
- **Three-tier, edit-specific warnings** (honest about real risk):
  - **Prompt edit (AI, same profile)** → *no duplicate risk* (uid scheme unchanged). Light
    "this might bring in older posts" backfill note; threshold optional.
  - **Source URL edit (same profile)** → possible repeats if the same content moved; warn, offer
    threshold.
  - **Profile change (uid scheme changes)** → recent items likely repeat; warn, **default the
    threshold on**. Caveat in copy: the threshold filters by *publication date*, so it's a
    strong-but-not-airtight guard for AI items that lack real dates — don't *promise* zero repeats.
- **Preview is not an enable-gate** — already true in code (`Feed#can_be_enabled?` checks name,
  active token, target group, profile, cron; not preview). Only leftover nicety: a disabled Preview
  button could explain what's missing instead of going inert.

### 5. Model selection & capability matrix

- **Model picker is gated to a curated, dev-verified allowlist** with a sensible default
  pre-selected and ignorable. Showing a model that can't do web+schema is a silent, async footgun;
  hiding the picker entirely throws away the per-feed flexibility shipped in #873.
- **Graceful degradation**: if a feed's selected model later drops out of the matrix, fall back to
  the provider's default supported model with a notice — don't start failing.
- **The matrix (`LlmModelCapability`) shrinks to its irreducible core**: a pure
  `(provider, model)` allowlist where *membership = qualification* (the pair is dev-verified to
  deliver structured output **and** web access together). **Drop tiers.** The two axes the old
  `tier` enum conflated both find better homes: *readiness* → dev-time compatibility testing (a pair
  enters only once verified; no `:experimental` rows in production); enforcement reliability is a
  provider property the adapter already embodies (§6), not a per-model flag.
- **What the matrix does NOT store** — these are fetched live from the provider (source of truth):
  - **Display names** — Anthropic `display_name`, OpenRouter `name`.
  - **Availability** — intersect the matrix with the credential's live models so a dropped model
    falls out on its own.
  - **Advertised structured-output support** — Anthropic `capabilities.structured_outputs`,
    OpenRouter `supported_parameters`.
- **Why a matrix is still required** (can't go fully dynamic): the two facts that actually gate an
  AI feed are *not* in either API — Anthropic per-model web-tool support (documented only by model
  family), and the *reliability of web+schema together* (the "Kimi flips to plain text" failure).
  Only dev testing reveals these; the matrix encodes exactly that verified set.

#### `LlmModelCapability` — implementation notes (trims #877 before merge)

- Remove `tier`, `TIERS`, `tier_for`, and the tier assertions; remove the `:experimental` rows
  (gemini, gpt-4o-mini, kimi). Keep `all`/`find`/`supported?`/`models_for` and the
  "membership = qualification" framing.
- Do **not** add a `label` field — display names are joined live from the provider models list.
- Add an invariant test: every `LlmProvider.default_model` is `supported?` by the matrix.
- Optional CI assertion: every matrix entry still advertises `structured_outputs` in the live API
  (early warning on silent provider changes).
- Follow-up tasks (named in #876): live intersection with `available_models`; display-name join for
  the picker; the dev-time compatibility probe (the gate that replaced the readiness tier).

### 6. Provider seam + two-step extraction

Verified against live Anthropic calls (Opus + Sonnet). Findings that shaped the design:

- RubyLLM 1.16 renders the current structured-output mechanism (`output_config.format`/`json_schema`
  for Anthropic, `response_format` for OpenRouter) and `with_params` deep-merges into the request —
  but RubyLLM has **no server-tool handling**: a web tool injected via `with_params` is mishandled by
  RubyLLM's function-tool loop the moment a schema is also set (it tries to run the server tool
  client-side and fails).
- A **raw** Anthropic call with `output_config.format` **and** web tools in one request **works**
  (HTTP 200, `end_turn`, clean schema JSON). So schema + web are *not* incompatible at the API — only
  through RubyLLM. We keep RubyLLM rather than maintain raw per-provider clients.
- Web alone (no schema) and schema alone (no web) each work cleanly *through* RubyLLM.

So AI extraction is **two RubyLLM calls**, never combining schema + web in one:

1. **Gather** — `web: true`, no schema. The model searches/fetches; `LlmClient` returns the raw text.
2. **Structure** — schema, `web: false`. The gathered text is fed in; `with_schema` returns clean,
   native JSON. No healing needed (so `SchemaHealer` stays dropped — §6 earlier rationale holds).

Supporting pieces:

- **Adapter** (`LlmClient::Adapter.for(provider)`), single responsibility `web_params(model) -> Hash`,
  injected via `with_params` **only on the gather call** (`web: true`):
  - Anthropic: server tools (`web_search_20260209`/`web_fetch_20260209`), citations off.
  - OpenRouter: web plugin + `require_parameters`. *(OpenRouter not yet live-verified.)*
- **`LlmClient#call(ctx, prompt:, output_schema:, web:)`** — injects web only when `web:`; returns the
  raw text when `output_schema` is nil, parsed+validated JSON when a schema is given. Keeps adapter
  selection, usage bookkeeping (one row per call → two per extraction), and the error taxonomy.
- **`UNIVERSAL_OUTPUT_SCHEMA` carries `additionalProperties: false`** on every object — Anthropic
  strict structured output rejects the schema without it (confirmed live).
- The `with_tool("web_search")` misuse is removed.

Latency note from live runs: gather dominates (web fetch), and varies widely by model/how much it
fetches (Opus ~12s, Sonnet ~40–120s); structure is cheap (~12s) and is a good Haiku candidate later.
The gather/structure prompts here are functional placeholders — Track 4 owns their final form and the
system-prompt safeguards.

### 7. Mode A detection & presentation

- Detection in Mode A is deterministic and **LLM-free**, so it can cheaply *test* each candidate
  (passed / couldn't-reach / won't-work). Presentation keys off the count of **working** candidates:
  - **0 working** (none matched, or the only match failed extraction) → error state (not the
    expanded form): *"Couldn't pull any posts from that link… AI can still follow it."* with
    **"Follow with AI instead"** (link, carries the URL into Mode B), *"Try a different link"*, and
    *Cancel* (→ feeds index).
  - **1 working** → no chooser; auto-select and show the **detected type as a plain annotation**
    (the profile's `display_name`, consistent with index/detail pages — not generated prose).
  - **≥2 working** → show the chooser ("How should we fetch posts?"), highest-specificity
    pre-selected. The *only* place "feed type" is a real choice; expected to be rare.
- **"Couldn't reach" ≠ "no feed"**: a transient network failure is a retry state, not the AI bridge.
- The AI bridge is **one-directional discovery**, never a silent fallback engine — Mode A never runs
  AI on its own; it only *offers* the door to Mode B.

### 8. System-prompt safeguards

Two safeguards earn a place in the prompt because they're aggregator-specific and the model won't do
them unprompted:

1. **Prompt-injection defense** — fetched/searched content is untrusted *data*, never instructions;
   the only instructions are the system prompt and the user's feed prompt.
2. **No fabrication / grounding** — only include items actually found via web tools; every item
   carries a real source URL; never invent posts, sources, or content (reinforces uid-as-permalink).

General harmful-content moderation is kept **minimal** — lean on the model's safety training and the
fact that the user authored the prompt and owns their feed; aggressive category-filtering would break
legitimate feeds (e.g. world news). **Prompt safeguards are defense-in-depth, not a security
boundary** — any *hard* guarantee belongs in the deterministic validation layer (normalizer/
processor), the same place the uid integrity checks live.

## Sequencing

- **AI plumbing + integrity first**: the per-provider seam (§6) and the `Uid::Resolver` (§3) are
  foundational and largely independent.
- **Single AI profile** (§2) depends on web access via the seam.
- **Explicit-mode creation** (§1, §7) depends on the single AI profile being what Mode B selects.
- **Editing/lifecycle** (§4) is largely independent; the prompt-editing win lands once §2 exists.
- The capability-matrix trim (§5) can land anytime; its follow-ups gate the picker work.

## Open / deferred

- Hourly digests (sub-day period granularity for standing queries) — emergent fallback only for now;
  a finer period is a later explicit feature.
- Disabled-Preview-button "what's missing" affordance — optional nicety.
- Confirm RubyLLM's Anthropic structured-output rendering is current (`output_config.format`) at
  implementation; if stale, the seam also owns schema injection.
