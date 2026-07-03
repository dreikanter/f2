# Feed Creation UX + AI Architecture Overhaul

**Date**: 2026-06-29, revised 2026-07-03 after design review |
**Status**: Design — Tracks 1–2 shipped (#880, #885); remaining tracks pre-implementation

**Related**: [`001-smart-feed-creation`](../001-smart-feed-creation/spec.md) (the flow this revises),
[`002-feed-drafts`](../002-feed-drafts/spec.md), [`003-unify-feed-preview-stack`](../003-unify-feed-preview-stack/spec.md),
[`004-manual-feed-preview`](../004-manual-feed-preview/spec.md) · PRs: #873 (per-feed provider/model),
#877 (capability matrix, WIP), #880 (Track 1: uid core), #885 (Track 2: provider seam)

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
  different prompts — redundant.
- Source/profile editing is locked in the UI from creation on (the expanded form renders the
  source and type as disabled fields even for drafts; strong params accept them draft-only). This
  is over-restrictive, and especially painful for AI feeds where the prompt *is* the source.
- The LLM stack leaked "how we talk to a provider" (structured output, web access) into the feed
  profile instead of behind a thin per-provider seam, and the old `with_tool("web_search")` call
  was a no-op misuse (RubyLLM `with_tool` is for function tools, not server tools) — fixed by
  Track 2.
- Preview is *believed* to gate enabling, but the code already does not gate on it.

## Core mental model

The user picks an **engine** (mechanism), not an input syntax. Two modes:

| | Mode A — "Follow a feed or channel" | Mode B — "Follow with AI" |
|---|---|---|
| Engine | Deterministic profiles (RSS, YouTube, Reddit, …) | Single AI profile (LLM + web access) |
| Input | A URL (single-line **"Source link"** field) | Free-form **"What should AI follow?"** textarea |
| Accepts | A link (scheme auto-fixed) or a deterministic shorthand (`r/x`) | A link, several links, or a description |

The **mode toggle** carries the mechanism; the **field label** carries the expected input type.
There is no auto-detection of input *shape* — the user stays in the engine they chose — but each
field *validates* form within its mode. A URL pasted into Mode B is fine (AI reads it — with a
cheaper-engine hint, see §1); a non-URL in Mode A is routed to Mode B via an inline bridge.

## Decisions

### 1. Entry & modes

- **Two explicit modes by mechanism**, labelled "Follow a feed or channel" / "Follow with AI".
  Drop shape auto-detection.
- **Two label slots, each with one job**: mode toggle = mechanism; field label = input type
  ("Source link" / "What should AI follow?"). Never overload one with both — that was the
  category error in the old single box.
- Mode A field: single-line input. **What counts as a URL**: an explicit `http(s)://` input, or
  one that **silent scheme-fix** turns into a parseable URL with a dotted host (`example.com` →
  `https://example.com`). The fix never applies to something that isn't host-shaped — `r/x` must
  not become `https://r/x` (host `r`), which would dead-end in the couldn't-reach state instead of
  reaching its matcher or the bridge. **Respect an explicit `http://`** for fetching (never force
  https — some feeds are http-only; uid identity is a separate concern, §3).
- **Deterministic shorthands stay**: inputs an existing matcher already resolves unambiguously
  (today: `r/x`, `user/x` → Reddit) enter Mode A detection as-is. Only genuinely ambiguous
  handles are not expanded — `@name` could be X, Telegram, or YouTube, and can't be resolved
  deterministically; those belong to the AI bridge. *(Revised: the original decision dropped
  `r/x` too, on the incorrect claim that it can't be resolved deterministically — the shipped
  Reddit matcher already does exactly that.)*
- **Failure taxonomy — two terminal exits, one transient state.** The terminal exits are the same
  exit: input isn't a URL or known shorthand (client-side, before any fetch), or it is a URL but
  yields no working feed (after detection). Both route to the **"Follow with AI instead"** bridge,
  carrying the input into Mode B. The transient state is not an exit: every candidate failed on
  network errors → retry state (§7), with retry primary and the bridge available as a secondary
  link so the state can't dead-end.
- **Mode B input**: non-blank free text with a generous ceiling (~2000 chars; the old 200-char
  `query` cap dies with shape auto-detection). Stored as the feed's prompt (§2).
- **Mode B flow after submit**: there is nothing to detect or test, so submission goes straight to
  the expanded form (no identification step) with a draft AI feed. The prompt stays editable as a
  textarea inside the form — unlike Mode A's read-only source display, because for AI feeds the
  prompt *is* the source and §4 unlocks it anyway. Name stays manual (AI profiles have no title
  extractor; a multi-line prompt is unusable as a default name). Default schedule: daily (§3,
  cadence).
- **Reverse hint (B→A)**: when a Mode B prompt is exactly one URL, run the LLM-free Mode A
  detection quietly; if a working deterministic candidate exists, offer a dismissible suggestion
  to use it instead — deterministic engines are cheaper and more reliable for the same source
  (001's cost-honesty principle). Never auto-switch, never block. Symmetric with the A→B bridge:
  each mode offers the other's door; neither silently falls through it.

### 2. AI feed model

- **Collapse the two AI profiles into one** (key: `llm`). Web access is intrinsic to the AI
  engine, not a per-profile toggle, so it leaves the profile config. There is no production data:
  the old `llm_website_extractor` / `llm_web_search` keys are deleted outright, no migration.
- **Input contract**: the prompt lives at `params["prompt"]` (`parameter_schema`: required
  `prompt`, 1–2000 chars). `Feed#source_input` and everything downstream resolve the storage key
  from the profile's parameter schema, **not** from `input_shape` — today the shape symbol doubles
  as the params key (`params["url"]`/`params["query"]`), which an `:any`-shaped profile would
  break (blank source display, dead previews, empty loader prompt). `input_shape` keeps only its
  mode-routing/validation job. The profile registers **no matcher** and is structurally excluded
  from detection (§7).
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
  **`normalize(permalink)`**: lowercase host, strip `utm_*`/fragments, canonicalize trailing
  slash. Two hardening rules on top:
  - **The uid is an identity key, not a fetch URL**: in the uid string only, coerce the scheme to
    `https` and strip default ports and a leading `www.`. Models flip `http/https` and `www`
    freely between runs; keeping them in the uid means duplicate reposts. The residual false-merge
    risk (two *different* articles distinguished only by `www.`) is accepted as negligible. No
    tension with §1's respect-explicit-http, which governs fetching.
  - **Non-ASCII/IDN permalinks are percent-encoded, not dropped** — today `URI.parse` raises on a
    raw Cyrillic path and the item silently vanishes.
- **The model never mints the uid string.** It signals the regime per item through one nullable
  schema field: **`source_url: string | null`**. A real permalink → feed-style → dedup. An
  explicit `null` → standing-query/digest → the **processor** mints a **period-keyed** uid using a
  trustworthy server clock (period = **UTC date of the run**; sub-day granularity stays deferred).
  There is no model-supplied "period hint" — period policy is entirely system-owned. The model has
  no reliable clock and must not stamp dates *for uid purposes*; it may pass through a
  `published_at` it actually read on the source (that's data; §4 covers how far it's trusted).
- **Unusable ≠ null.** Regime is the explicit signal only. A feed-style item whose permalink is
  present but unusable (unparseable, non-http, bare homepage) is **dropped and counted** — never
  reinterpreted as a digest. Otherwise one bad URL consumes the day's period slot with the wrong
  content.
- **"One digest post per period" is enforced, not assumed**: the processor **collapses items to
  unique final uids within a batch** (keep-first; collapsed count recorded). Without the collapse,
  two same-uid items in one run hit the DB unique index through `insert_all`, roll back the
  *entire* batch, and — via consecutive-failure counting — auto-disable the feed after 10 runs.
  That crash is already reachable today in the permalink regime (the model listing one article
  twice: a `utm_` variant plus the clean URL). **The collapse ships immediately, ahead of
  Track 4** (see Sequencing). It also makes mixed-regime batches coherent by construction.
- **Placement is load-bearing — all the way down.** `filter_new_entries` (dedup) and the blank-uid
  drop run *after* `process_feed_contents`, so the uid must be final by the end of that step; uid
  minting lives in `PassthroughProcessor` (mirroring `RssProcessor#extract_uid`), delegating
  policy to the unit-tested `Uid::Resolver` (shipped, Track 1; Track 4 adds the clock + regime
  input). But the digest regime must also survive the layers *after* the uid guards: today the LLM
  normalizer rejects any item without `source_url`, `Post` validates its presence, and the column
  is `NOT NULL` — a null-permalink digest post would persist its period uid and then land
  permanently `rejected`: the period slot consumed, nothing published, every run "successful".
  **Decision**: digest posts carry `source_url = null` end-to-end — normalizer carve-out for the
  digest regime, `Post` validation made conditional, column made nullable; a digest cites its
  sources inline in the body (§8). Track 4 owns this alongside the schema change.
- **Run cadence vs period**: a digest feed on the default 2-hourly schedule would pay the full
  gather+structure cost ~12×/day and discard 11 results as same-period dups. Mode B feeds default
  to a **daily** schedule; additionally, when a feed's *previous* run produced only period-keyed
  uids and that period is still current, the scheduled run is **skipped before any LLM call**
  (recorded as skipped). Mixed or feed-style outputs never skip.

### 4. Editing & lifecycle

- **Unlock** source/profile/prompt editing (controller strong-params + the disabled form fields in
  `_form_expanded.html.erb` — which today disable these fields from creation on, drafts included).
- **Engine is fixed at creation**: a feed never switches deterministic ↔ AI in edit — create a new
  feed instead. This bounds the uid-scheme blast radius, keeps the edit form in a single mode, and
  keeps the tier-3 warning below scoped to *deterministic → deterministic* profile changes.
- **Source edits re-run detection**: changing a Mode A feed's source URL re-runs identification +
  candidate testing before save, reusing §7's presentation states (annotation / chooser / no-feed /
  couldn't-reach) — an edit that yields no working candidate doesn't silently save a feed that
  fails on every refresh. AI prompt edits are free-form (bounds only, no detection).
- **`import_after` is the single user-owned backlog lever**, not a dedup mechanism. No silent
  baseline reseed — a reseed can't match revision-2 items against revision-1 items, so it would
  silently swallow transition-window posts (a worse, invisible failure than the duplicates it
  prevents).
- **Three-tier, edit-specific warnings** (honest about real risk):
  - **Prompt edit (AI, same profile)** → *no duplicate risk* (uid scheme unchanged). Light
    "this might bring in older posts" backfill note; threshold optional. For a digest feed, a
    mid-period prompt edit takes effect **next period** (the current slot is already consumed) —
    no duplicates, at most one skipped digest.
  - **Source URL edit (same profile)** → possible repeats if the same content moved; warn, offer
    threshold.
  - **Profile change (deterministic → deterministic; uid scheme changes)** → recent items likely
    repeat; warn, **default the threshold on**. Caveat in copy: the threshold filters by
    *publication date*; AI items keep a model-extracted `published_at` only when the source
    displayed one and fall back to first-seen time otherwise, so for dateless items the threshold
    is a no-op, not merely weak — permalink dedup is the real guard. Don't *promise* zero repeats.
- **Preview is not an enable-gate** — already true in code (`Feed#can_be_enabled?` checks name,
  active token, target group, profile, cron; not preview). Only leftover nicety: a disabled Preview
  button could explain what's missing instead of going inert.

### 5. Model selection & capability matrix

- **Model picker is gated to a curated, dev-verified allowlist** with a sensible default
  pre-selected and ignorable. Showing a model that can't do web+schema is a silent, async footgun;
  hiding the picker entirely throws away the per-feed flexibility shipped in #873.
- **Where validation sits (one rule for every surface)**: `ai_model` membership is validated
  **when it changes** — the form offers only matrix ∩ the credential's model snapshot. A feed
  whose saved model later drops out never blocks unrelated edits, and never hard-fails preview or
  scheduled runs: **both** resolve to the provider's default supported model and record an
  **Event** (the "notice", surfaced on the feed page like other feed events). Today the code does
  three different things — blocks save, blocks preview, silently keeps using the dropped model at
  run time — and §4's unlock would turn the save-block into a trap.
- **The matrix (`LlmModelCapability`) shrinks to its irreducible core**: a pure
  `(provider, model)` allowlist where *membership = qualification* — the pair is dev-verified to
  deliver **the §6 two-step contract: web gather and strict-schema structure as separate calls**
  (not "together" in one request, a shape §6 abolished). When per-step models land (the Haiku
  structure candidate), the matrix grows a role dimension; until then a row qualifies a model for
  both steps. **Drop tiers.** The two axes the old `tier` enum conflated both find better homes:
  *readiness* → dev-time compatibility testing (a pair enters only once verified; no
  `:experimental` rows in production); enforcement reliability is a provider property the adapter
  already embodies (§6), not a per-model flag.
- **What the matrix does NOT store** — these come from the **credential's models snapshot**
  (captured at credential validation, not a per-render live call):
  - **Display names** — Anthropic `display_name`, OpenRouter `name`.
  - **Availability** — intersect the matrix with the snapshot so a dropped model falls out on its
    own (at snapshot refresh).
  - **Advertised structured-output support** — Anthropic `capabilities.structured_outputs`,
    OpenRouter `supported_parameters`.
- **Why a matrix is still required** (can't go fully dynamic): the two facts that actually gate an
  AI feed are *not* in either API — Anthropic per-model web-tool support (documented only by model
  family), and the *reliability of web+schema together* (the "Kimi flips to plain text" failure).
  Only dev testing reveals these; the matrix encodes exactly that verified set.
- **Per-provider availability**: a provider without verified matrix rows (OpenRouter, until its
  web path is live-verified — §6) isn't selectable for AI feeds, stated plainly in the picker.
  This unblocks the matrix trim landing "anytime" without waiting on OpenRouter verification.

#### `LlmModelCapability` — implementation notes (trims #877 before merge)

- Remove `tier`, `TIERS`, `tier_for`, and the tier assertions; remove the `:experimental` rows
  (gemini, gpt-4o-mini, kimi). Keep `all`/`find`/`supported?`/`models_for` and the
  "membership = qualification" framing.
- Do **not** add a `label` field — display names are joined from the credential's models snapshot.
- Add an invariant test: for every provider **with matrix rows**, its `default_model` is
  `supported?` by the matrix.
- Optional CI assertion: every matrix entry still advertises `structured_outputs` in the live API
  (early warning on silent provider changes).
- Follow-up tasks (named in #876): intersection with the credential snapshot; display-name join for
  the picker; the dev-time compatibility probe (the gate that replaced the readiness tier).

### 6. Provider seam + two-step extraction

*(Shipped as Track 2, #885 — kept as rationale. The gather-empty guard, the usage `step` field,
the preview budget, and the inline-schema fix below are still open.)*

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
- **Gather-empty guard**: if the gather step returns blank/whitespace, the run yields zero items —
  the structure step is skipped and an event recorded. Feeding emptiness (or a refusal) into the
  structure call invites fabricated items, exactly what §8 forbids.
- **`UNIVERSAL_OUTPUT_SCHEMA` carries `additionalProperties: false`** on every object — Anthropic
  strict structured output rejects the schema without it (confirmed live). **Known gap to fix
  before Track 4**: `llm_website_extractor`'s loader config still embeds its own inline schema
  *without* the marker, so by this section's own live-verified finding the profile's structure
  step fails on Anthropic strict. Point it at `UNIVERSAL_OUTPUT_SCHEMA` (one line) now rather than
  waiting for the collapse.
- Usage bookkeeping gains a **`step` discriminator** (gather/structure) on `LlmUsage`, and
  `CallContext` carries the model per call — so the deferred per-step-model optimization won't
  have to rework accounting, and the two rows per extraction stop being indistinguishable.
- The `with_tool("web_search")` misuse is removed.

Latency note from live runs: gather dominates (web fetch), and varies widely by model/how much it
fetches (Opus ~12s, Sonnet ~40–120s); structure is cheap (~12s) and is a good Haiku candidate later.
**The preview stack must absorb this**: the current polling budget (~85–90s server and client) is
below these numbers, so a default-model AI preview can be marked failed while the job is still
legitimately working — and later flip failed→ready after the user gave up. AI previews get a longer
budget (~4 minutes), progress copy that says AI is browsing the web, and a timeout that is terminal
for that run. The gather/structure prompts here are functional placeholders — Track 4 owns their
final form and the system-prompt safeguards.

### 7. Mode A detection & presentation

- Detection in Mode A is deterministic and **LLM-free**, so it can cheaply *test* each candidate
  (passed / couldn't-reach / won't-work). Presentation keys off the count of **working** candidates:
  - **0 working** splits by *why*: if at least one candidate was reachable and none yields a feed →
    the terminal error state (not the expanded form): *"Couldn't pull any posts from that link… AI
    can still follow it."* with **"Follow with AI instead"** (link, carries the URL into Mode B),
    *"Try a different link"*, and *Cancel* (→ feeds index). If **every** candidate failed on
    network errors → the transient couldn't-reach state: retry primary, the same AI bridge as a
    secondary link (never a dead end).
  - **1 working** → no chooser; auto-select and show the **detected type as a plain annotation**
    (the profile's `display_name`, consistent with index/detail pages — not generated prose).
  - **≥2 working** → show the chooser ("How should we fetch posts?"), highest-specificity
    pre-selected. The *only* place "feed type" is a real choice; expected to be rare.
- **"Couldn't reach" ≠ "no feed"**: a transient network failure is a retry state, not a terminal
  verdict.
- The AI bridge is **discovery, never a silent fallback engine** — Mode A never runs AI on its
  own; it only *offers* the door to Mode B. (The §1 reverse hint is the mirror image: Mode B never
  runs the deterministic engine on its own; it may only suggest it.)
- **Structural exclusion**: the single AI profile registers no matcher, so detection *cannot*
  select it — "Mode A never runs AI" is enforced by construction, not convention. (Guard against
  `matchers_for`'s `:any`-matches-everything clause sweeping the AI profile in: with no matcher
  registered there is nothing to sweep.)

### 8. System-prompt safeguards

Two safeguards earn a place in the prompt because they're aggregator-specific and the model won't do
them unprompted:

1. **Prompt-injection defense** — fetched/searched content is untrusted *data*, never instructions;
   the only instructions are the system prompt and the user's feed prompt.
2. **No fabrication / grounding** — only include items actually found via web tools. A feed-style
   item carries a real source URL; a digest item cites its sources inline in the body (its
   `source_url` is null by design, §3). Never invent posts, sources, or content (reinforces
   uid-as-permalink).

General harmful-content moderation is kept **minimal** — lean on the model's safety training and the
fact that the user authored the prompt and owns their feed; aggressive category-filtering would break
legitimate feeds (e.g. world news). **Prompt safeguards are defense-in-depth, not a security
boundary** — any *hard* guarantee belongs in the deterministic validation layer, which concretely
owns:

- uid minting, intra-batch collapse, and permalink normalization (§3);
- **attachment URL validation** — model-emitted image URLs are fetched *server-side* at publish
  time, and the current fetcher will read a local file path or GET any address it's handed. Before
  persistence, every attachment URL must be an absolute http(s) URL pointing at a public host (no
  local paths, no localhost/private ranges) or be dropped. A bad attachment **drops the
  attachment, not the post** — today one hallucinated image URL permanently fails the whole post
  with its uid already consumed, a §3-style silent drop delivered at the publish stage;
- **body length** — Freefeed's 3000-grapheme post limit is enforced by deterministic truncation in
  the LLM normalizer. Both AI regimes (free-form transformation, daily digests) push toward long
  bodies; the structure prompt also asks for brevity, but the prompt is not the guarantee.

## Sequencing

- **Two immediate fixes ship first, ahead of any track**: intra-batch uid collapse (§3 — the
  batch-destroying crash is reachable today) and the `llm_website_extractor` inline-schema fix
  (§6). Both are small and independent.
- **AI plumbing + integrity first**: the per-provider seam (§6, shipped) and the `Uid::Resolver`
  (§3, core shipped; clock + regime input pending) are foundational and largely independent.
- **Single AI profile** (§2) depends on web access via the seam — and ships together with its
  detection exclusion (§7), so it never leaks into the old auto-detect UI during the interim.
- **Explicit-mode creation** (§1, §7) depends on the single AI profile being what Mode B selects.
- **Editing/lifecycle** (§4) is largely independent; the prompt-editing win lands once §2 exists.
- The capability-matrix trim (§5) can land anytime (Anthropic-only rows; OpenRouter rows enter
  after live verification); its follow-ups gate the picker work.

## Open / deferred

- Hourly digests (sub-day period granularity for standing queries) — emergent fallback only for now;
  a finer period is a later explicit feature.
- Per-step models (the Haiku structure candidate) — deferred; accounting is prepared via the usage
  `step` field and per-call model in `CallContext` (§6).
- Disabled-Preview-button "what's missing" affordance — optional nicety.
- Reverse-hint (§1) copy and exact trigger — lightweight; ship with Mode B or just after.
