# Feed Creation UX + AI Architecture Overhaul

**Date**: 2026-06-29, revised 2026-07-03 after design review |
**Status**: Implemented — Tracks 1–2 (#880, #885) plus Tracks 3–4 (single AI profile, two-mode
creation, capability-matrix trim, digest regime + cadence skip, editing unlocks, production prompts +
safeguards, attachment/SSRF validation) shipped across #903–#942. Deferred: the usage `step`
discriminator (§6). Dropped: the Mode B→A reverse hint (§1).

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
| Accepts | A link (scheme auto-fixed) | A link, several links, or a description |

The **mode toggle** carries the mechanism; the **field label** carries the expected input type.
There is no auto-detection of input *shape* — the user stays in the engine they chose — but each
field *validates* form within its mode. A URL pasted into Mode B is fine (AI reads it — a
cheaper-engine hint was considered and dropped, see §1); a non-URL in Mode A is routed to Mode B via
an inline bridge.

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
  reaching the bridge. **Respect an explicit `http://`** for fetching (never force
  https — some feeds are http-only; uid identity is a separate concern, §3).
- **No shorthand expansion.** `r/x` and `@handle` are not special-cased: a subreddit is followed by
  pasting its full URL; ambiguous handles belong to the AI bridge. Reddit doesn't warrant special
  input treatment — the shipped matcher's bare-`r/x` patterns can go with the old smart input.
- **Failure taxonomy — two terminal exits, one transient state.** The terminal exits are the same
  exit: input isn't a URL (client-side, before any fetch), or it is a URL but
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
- **Reverse hint (B→A) — dropped.** The idea: when a Mode B prompt is exactly one URL, quietly run
  the LLM-free Mode A detection and, if a working deterministic candidate exists, offer a dismissible
  "follow it directly instead" suggestion — deterministic engines are cheaper and more reliable for
  the same source (001's cost-honesty principle), never auto-switching. **Not built**: a correct
  version needs the async detection job surfaced non-disruptively inside the AI form (RSS detection
  needs the *fetched page body*, so there's no cheap URL-pattern shortcut), and the payoff didn't
  justify that machinery. The A→B bridge (§7) ships; this mirror direction does not.

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
  policy to the unit-tested `Uid::Resolver` (shipped — the clock + regime input landed too:
  `call(item, clock:)`, `digest?` on an explicit-null `source_url`, and `digest_period_uid`). But
  the digest regime must also survive the layers *after* the uid guards: today the LLM
  normalizer rejects any item without `source_url`, `Post` validates its presence, and the column
  is `NOT NULL` — a null-permalink digest post would persist its period uid and then land
  permanently `rejected`: the period slot consumed, nothing published, every run "successful".
  **Decision**: digest posts carry `source_url = null` end-to-end — normalizer carve-out for the
  digest regime, `Post` validation made conditional, column made nullable; a digest cites its
  sources inline in the body (§8). *(Shipped: `LlmNormalizer` carve-out, `validates :source_url,
  presence: true, allow_nil: true`, and a nullable `posts.source_url`.)*
- **Run cadence vs period**: a digest feed on the default 2-hourly schedule would pay the full
  gather+structure cost ~12×/day and discard 11 results as same-period dups. Mode B feeds default
  to a **daily** schedule; additionally, when a feed's *previous* run produced only period-keyed
  uids and that period is still current, the scheduled run is **skipped before any LLM call**
  (recorded as skipped). Mixed or feed-style outputs never skip. *(Shipped: the skip signal is the
  feed schedule's `last_digest_period`, recorded from the actually-minted uid — so a run finishing
  past UTC midnight records the day it served, not the next. A **manual** refresh always forces
  through.)*

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
  active token, target group, profile, cron; not preview). The leftover nicety — a disabled Preview
  button explaining what's missing (a source, an AI provider, or a model) instead of going inert —
  has since shipped.

### 5. Model selection & capability matrix

*(Live-verified: [`plan-03-provider-verification.md`](./plan-03-provider-verification.md). Anthropic
Sonnet qualified; Kimi qualified for fetch-only feeds; OpenRouter dropped as unpayable. Verdicts
below reflect that record.)*

- **Model picker is gated to a curated, dev-verified allowlist** with a sensible default
  pre-selected and ignorable. Showing a model that can't do the capability a feed needs is a silent,
  async footgun; hiding the picker entirely throws away the per-feed flexibility shipped in #873.
- **Where validation sits (one rule for every surface)**: `ai_model` membership is validated
  **when it changes** — the form offers only matrix ∩ the credential's model snapshot. A feed
  whose saved model later drops out never blocks unrelated edits, and never hard-fails preview or
  scheduled runs: **both** resolve to the provider's default supported model and record an
  **Event** (the "notice", surfaced on the feed page like other feed events). Today the code does
  three different things — blocks save, blocks preview, silently keeps using the dropped model at
  run time — and §4's unlock would turn the save-block into a trap.
- **The matrix (`LlmModelCapability`) shrinks to its irreducible core**: a `(provider, model)`
  allowlist where *membership = qualification*. Verification (plan-03) showed qualification is not a
  single flag but a **capability set** — a pair is dev-verified for some of {fetch, search,
  structured-output}, not necessarily all. Kimi qualifies for fetch + structure (via client-side
  tools, §6) but **not** search; Anthropic Sonnet qualifies for all three. The matrix records which
  capabilities each pair is verified for, so Mode B can offer a cheap fetch-only provider without
  pretending it can run discovery feeds. **Drop tiers.** The two axes the old `tier` enum conflated
  both find better homes: *readiness* → dev-time compatibility testing (a pair enters only once
  verified; no `:experimental` rows in production); enforcement reliability is a provider property
  the adapter already embodies (§6), not a per-model flag.
- **What the matrix does NOT store** — these come from the **credential's models snapshot**
  (captured at credential validation, not a per-render live call):
  - **Display names** — Anthropic `display_name`; provider-native model name otherwise.
  - **Availability** — intersect the matrix with the snapshot so a dropped model falls out on its
    own (at snapshot refresh).
  - **Advertised structured-output support** — from the provider's model metadata where exposed.
- **Why a matrix is still required** (can't go fully dynamic): the facts that actually gate an AI
  feed are *not* in any provider API and only dev testing reveals them — Anthropic per-model
  web-tool support (documented only by model family); the reliability of structured output itself
  (Kimi fences its JSON ~⅔ of runs even under `response_format: json_schema`, plan-03); and whether
  a provider's web tools engage at all through RubyLLM (Kimi's builtin `$web_search` never fires —
  it imitates the tool as plain text). The matrix encodes exactly that verified capability set.
- **Per-provider availability**: a provider with no verified rows isn't selectable for AI feeds,
  stated plainly in the picker — this is why OpenRouter (unpayable, dropped) and any unverified
  provider simply don't appear, and why the matrix trim can land without waiting on them.

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

### 6. Provider seam + retrieval + structured output

*(Shipped as Track 2, #885 — kept as rationale. Since shipped: the gather-empty guard, the preview
budget, and the inline-schema fix (obviated by §2's single-profile collapse). Still open: the usage
`step` discriminator.)*

**Update (plan-03, live-verified 2026-07-05).** Two premises below have since been overtaken by
evidence; kept for the record with the correction inline:

- **Anthropic: schema + web now work *combined* in one RubyLLM call.** The original "never combine"
  rule was a RubyLLM limitation that no longer holds on RubyLLM 1.16 — a single Anthropic call with
  a schema *and* server web tools returns grounded, schema-valid JSON. So for Anthropic the two-step
  split is optional: a single combined call is cheaper (one usage row), faster, and loses no
  intermediate text. Two-step stays a supported fallback shape; it is no longer the required default.
- **Retrieval is per-provider, and the seam carries it.** Anthropic uses provider-hosted server
  tools. **Kimi's builtin `$web_search` does not engage through RubyLLM** (it imitates the tool as
  plain text; forcing it 400s against thinking mode), and Kimi **fences its JSON ~⅔ of runs** even
  under `response_format: json_schema`. Kimi is therefore driven with **client-side function tools**
  (a fetch tool works and grounds; a *search* tool would need an external search API — deferred) plus
  a deterministic `unfence` on the structure step (a single string op, provider-scoped, **not** LLM
  healing — the strict no-heal rule holds for providers that don't need it). See §5's capability-set
  matrix and plan-03 for the fetch-only-vs-search scoping.

Original Anthropic findings that shaped the two-step design (Opus + Sonnet):

- RubyLLM 1.16 renders the current structured-output mechanism (`output_config.format`/`json_schema`
  for Anthropic, `response_format` for OpenRouter) and `with_params` deep-merges into the request —
  but RubyLLM has **no server-tool handling**: a web tool injected via `with_params` is mishandled by
  RubyLLM's function-tool loop the moment a schema is also set (it tries to run the server tool
  client-side and fails).
- A **raw** Anthropic call with `output_config.format` **and** web tools in one request **works**
  (HTTP 200, `end_turn`, clean schema JSON). So schema + web are *not* incompatible at the API — only
  through RubyLLM. We keep RubyLLM rather than maintain raw per-provider clients.
- Web alone (no schema) and schema alone (no web) each work cleanly *through* RubyLLM.

So AI extraction **branches per provider** (via `Adapter#combined_extraction?`), reconciling the
original two-step design with the plan-03 combined-call finding above:

1. **Anthropic — combined.** One RubyLLM call carries the system prompt, the schema, *and* web tools
   together (`combined_extraction? == true`): grounded, schema-valid JSON in a single usage row.
2. **Moonshot / OpenRouter — two-step.** **Gather** (`web: true`, no schema; `LlmClient` returns raw
   text) then **Structure** (schema, `web: false`; `with_schema` returns native JSON). No healing
   needed, so `SchemaHealer` stays dropped.

Supporting pieces:

- **Adapter** (`LlmClient::Adapter.for(provider)`) applies web access on the **web-enabled call**
  (`web: true` — the combined call for Anthropic, the gather call for two-step providers):
  - Anthropic: `with_params` server tools (`web_search_20260209`/`web_fetch_20260209`), citations off.
  - Moonshot: a client-side `WebFetch` function tool (the builtin `$web_search` doesn't engage; §5/plan-03).
  - OpenRouter: `with_params` web plugin + `require_parameters`. *(OpenRouter not yet live-verified.)*
- **`LlmClient#call(ctx, prompt:, output_schema:, web:, system:)`** — routes `system:` to the chat as
  instructions (the §8 safeguards channel), injects web only when `web:`; returns the raw text when
  `output_schema` is nil, parsed+validated JSON when a schema is given. Keeps adapter selection, usage
  bookkeeping (one row per call — two per extraction on two-step providers, one on Anthropic combined),
  and the error taxonomy.
- **Gather-empty guard** *(shipped)*: if the gather step returns blank/whitespace, the run yields
  zero items — the structure step is skipped and a `feed_refresh_ai_empty` event recorded. Feeding
  emptiness (or a refusal) into the structure call invites fabricated items, exactly what §8 forbids.
- **`UNIVERSAL_OUTPUT_SCHEMA` carries `additionalProperties: false`** on every object — Anthropic
  strict structured output rejects the schema without it (confirmed live). *(The former
  `llm_website_extractor` inline-schema gap is moot: §2's collapse deleted that profile, and the
  single `llm` profile's loader config points at `UNIVERSAL_OUTPUT_SCHEMA`.)*
- Usage bookkeeping is to gain a **`step` discriminator** (gather/structure) on `LlmUsage` so the
  two rows per extraction stop being indistinguishable — *not yet added* (the one still-open §6
  item). `CallContext` already carries the model per call, so the deferred per-step-model
  optimization won't have to rework that half of the accounting.
- The `with_tool("web_search")` misuse is removed.

Latency note from live runs: gather dominates (web fetch), and varies widely by model/how much it
fetches (Opus ~12s, Sonnet ~40–120s); structure is cheap (~12s) and is a good Haiku candidate later.
**The preview stack must absorb this**: the current polling budget (~85–90s server and client) is
below these numbers, so a default-model AI preview can be marked failed while the job is still
legitimately working — and later flip failed→ready after the user gave up. AI previews get a longer
budget (~4 minutes), progress copy that says AI is browsing the web, and a timeout that is terminal
for that run. *(Shipped: the gather/structure/combined prompts now live in production form in
`Loader::LlmPrompts` — task, output contract, and the §8 safeguards — delivered through the `system:`
channel above.)*

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
  own; it only *offers* the door to Mode B. (The mirror direction — Mode B suggesting the
  deterministic engine, §1's reverse hint — was dropped; either way Mode B never runs detection on
  its own.)
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
  with its uid already consumed, a §3-style silent drop delivered at the publish stage. *(Shipped:
  `Normalizer::Base#attachment_urls` filters through `PublicUrl.safe?` at the shared choke point, so
  it covers every feed type, not just AI. Two fetch-layer refinements followed from review — HTTP
  redirect hops are validated per hop, since a public URL can 302 to a private address; the DNS
  resolve-and-pin residual is tracked in #941.)*;
- **body length** — Freefeed's 3000-grapheme post limit is enforced by deterministic truncation in
  the LLM normalizer. Both AI regimes (free-form transformation, daily digests) push toward long
  bodies; the structure prompt also asks for brevity, but the prompt is not the guarantee.

## Sequencing

- **Two immediate fixes ship first, ahead of any track**: intra-batch uid collapse (§3 — the
  batch-destroying crash is reachable today) and the LLM profile's inline-schema fix (§6 — obviated
  once §2 collapsed to the single `llm` profile on `UNIVERSAL_OUTPUT_SCHEMA`). Both were small and
  independent.
- **AI plumbing + integrity first**: the per-provider seam (§6, shipped) and the `Uid::Resolver`
  (§3, shipped including the clock + regime input) are foundational and largely independent.
- **Single AI profile** (§2) depends on web access via the seam — and ships together with its
  detection exclusion (§7), so it never leaks into the old auto-detect UI during the interim.
- **Explicit-mode creation** (§1, §7) depends on the single AI profile being what Mode B selects.
- **Editing/lifecycle** (§4) is largely independent; the prompt-editing win lands once §2 exists.
- The capability-matrix trim (§5) can land anytime (Anthropic-only rows; OpenRouter rows enter
  after live verification); its follow-ups gate the picker work.

## Open / deferred

- Hourly digests (sub-day period granularity for standing queries) — emergent fallback only for now;
  a finer period is a later explicit feature.
- Per-step models (the Haiku structure candidate) — deferred. `CallContext` already carries a
  per-call model; the usage `step` discriminator that would make the two rows distinguishable is
  **not yet added** (the one still-open §6 item).
- Reverse-hint (§1, Mode B→A) — **dropped**, not deferred: the async detection a correct version
  needs isn't worth the payoff (see §1).
