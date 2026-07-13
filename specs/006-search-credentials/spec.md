# Search Credentials: Managed Per-User Keys for Web Search

**Date**: 2026-07-13 |
**Status**: Draft — nothing shipped yet. Supersedes the interim ENV-based key resolution from #980.

**Related**: [`005-feed-creation-ux-ai-overhaul`](../005-feed-creation-ux-ai-overhaul/spec.md)
(§5 capability matrix, §6 provider seam/retrieval),
[`plan-03-provider-verification`](../005-feed-creation-ux-ai-overhaul/plan-03-provider-verification.md) ·
Issues/PRs: #980 (WebSearchProvider + search tool + Moonshot wiring), #983 (this design's ticket)

This is the design/rationale record for bringing web search up to the same "managed per-user
credential" footing as LLM access. It may ship across multiple PRs. Where the code later diverges,
the code is the source of truth; this document records *why* the decisions were made.

## Why

- #980 landed `WebSearchProvider` (Serper / Brave / Tavily behind one normalized interface) with
  key resolution explicitly scaffolded on ENV (`WebSearchProvider.default`, `ENV_KEYS`). That seam
  was always meant to be replaced by a managed model mirroring `AiCredential`.
- Search must be **personalized, managed API access**: a user brings their own search-provider
  key; searches bill to their account; usage is attributable per credential.
- Native provider-hosted search is expensive and opaque: Anthropic bills ~$10/1K searches and
  OpenRouter's web plugin ~$4/1K, both invisible to our accounting; external SERP APIs run
  $0.30–5/1K and every call passes through our code. External search is therefore both the cheap
  option and the only attributable one.
- Today a search failure is invisible: the tool swallows every `WebSearchProvider::Error` into an
  in-band `{ error: }` the model reads; worst case is an empty gather with a debug event. With a
  *paid, user-owned* key behind the tool, silent degradation is unacceptable.

## Core mental model

A search credential is the **second required key of every AI feed**, structurally identical to the
AI credential the user already knows: same lifecycle, same management pages, same per-feed picker,
same enable-gating, same deactivation blast radius. One new concept class (a credential for a
different provider registry), zero new interaction patterns.

| | AI credential (exists) | Search credential (this spec) |
|---|---|---|
| Provider registry | `LlmProvider` | `WebSearchProvider::REGISTRY` |
| Model | `AiCredential` | `SearchCredential` |
| Validation | free models-endpoint call | **one real search** (`max_results: 1`) |
| Feed link | `ai_credential_id`, required for AI feeds | `search_credential_id`, required for AI feeds |
| Runtime consumer | `LlmClient` adapters | client-side `WebSearch` tool, all providers |
| Usage record | `LlmUsage` rows | debug **Events** (counts now, cost later) |

## Decisions

### 1. `SearchCredential` model + management UI — mirror `AiCredential`

- Per-user, encrypted `credential_data` (`{ "api_key" => ... }`), `provider` validated against
  `WebSearchProvider::REGISTRY`, display name with the same `NameGenerator` auto-naming, state
  machine `pending → validating → active | inactive`, `last_validated_at` / `last_error`.
- Management UI is a 1:1 copy of the `ai_credentials` stack: controller, policy, components,
  views, `resources :search_credentials` with the nested singular `validation` (polling) and
  `default` resources. Standalone settings section — its own settings card and nav entry, a peer
  of AI Credentials.
- User-level `default_search_credential` mirrors `default_ai_credential` **including its
  preselection-only semantics**: it preselects the picker in the feed form and is never consulted
  at run time. Runtime always reads `feed.search_credential`.
- Empty-state copy explains the dependency plainly: AI feeds need a search key to search the web;
  non-AI feeds never need one.

### 2. Validation: one real billed query, not optimistic-active

#983 floated marking new keys active optimistically to avoid burning a search credit per save.
Rejected: the codebase deliberately prevents search failures from surfacing at run time (the tool
returns errors in-band to the model only), so "surface failures on first use" has no mechanism —
an invalid key would stay green-checked "Active" forever while feeds degrade. Optimistic-active
also breaks the copied UI, whose entire show-page lifecycle (polling, spinner, active/inactive
alerts, `credential_status_icon` where active means *verified*) is validation-shaped.

- `SearchCredentialValidationJob` mirrors `AiCredentialValidationJob`: `pending → validating`; one
  fixed innocuous query with `max_results: 1` through the resolved provider; success → `active`;
  `WebSearchProvider::Error` → `inactive` + `last_error`. The whole copied lifecycle then works
  verbatim with honest semantics. The billed query costs a fraction of a cent on every registered
  provider.
- **Deliberate divergence from the mirror**: re-validate only when a new key is submitted.
  The AI side resets to pending and re-runs validation on *every* update, including name-only
  edits — copied literally that bills a query per rename.
- Validation searches record the per-call event (§6) with no feed-refresh reference.

### 3. Client-side search for every AI provider — retire native search

Every adapter drives the credential-backed client-side `WebSearch` tool. Anthropic's server-side
`web_search` tool and OpenRouter's `web` plugin are removed as search paths.

- **Cheaper**: external SERP pricing is 4–30× below native search fees.
- **Consistent**: one search behavior and one result shape across providers, instead of
  native-vs-external switching per adapter. This also unblocks search-capable Kimi feeds —
  plan-03 deferred them precisely because an external search API was missing.
- **Attributable**: every search passes through our code, so it can be counted per credential and
  costed later. Native search fees never appear in any accounting we control.
- Consequence for the capability matrix (005 §5): the "search" capability now means "reliably
  drives the client-side search tool" for every provider. Anthropic must be re-verified driving
  function-tool search alongside structured output; Kimi and any future provider verify against
  the same single path.
- Fetch is a separate concern: whether Anthropic keeps its server-side `web_fetch` tool or moves
  to the client-side `WebFetch` tool is decided during adapter work with live verification.
  Search, in either case, goes through the credential-backed tool.

### 4. Feed association: `search_credential_id`, required for AI feeds only

- Nullable `search_credential_id` FK on `Feed`, mirroring `ai_credential_id` end to end:
  same-user validation, required-when-enabled validation **scoped to AI profiles**,
  `can_be_enabled?` gating, picker preselection order (feed's own credential, then the user
  default, then the first selectable). Non-AI feeds never see or need it.
- The feed form gains a required search-credential picker in the AI settings area. The
  add-credentials gate extends to cover both credential types: the gate panel lists whichever of
  the two is missing, and each "add" detour round-trips back to the draft via the existing
  `feed_id` mechanism independently — no chained detour, the gate simply re-renders with one item
  left.
- There is no per-feed reason to prefer one search vendor over another today (results are
  normalized to identical tuples), but the FK is still the right shape: it matches the AI
  credential pattern exactly, keeps preview parity trivial (§7), and per-feed assignment is what
  makes deactivation blast radius (§5) and per-feed usage attribution (§6) well-defined.

### 5. Lifecycle and failure semantics: search is load-bearing

An AI feed cannot do its job without search — the model cannot invent grounded content (005 §8).
So search failures follow the AI-credential playbook, with no enhancement-style carve-outs:

- **Inactive search credential blocks the feed**: enablement validation and `can_be_enabled?`
  treat a missing or non-active search credential exactly like a missing AI credential.
- **Deactivation disables dependent feeds** — full `disable_credential_and_feeds` semantics
  (inactive + `last_error`, warning `search_credential_deactivated` event, enabled feeds
  disabled), and on destroy the FK is nullified and enabled feeds disabled, mirroring
  `disable_dependent_feeds`.
- **Typed errors are the prerequisite.** `WebSearchProvider`'s taxonomy grows an `AuthError`
  (HTTP 401/403, and 402/quota-exhausted) distinct from transient `ProviderError`. Auth errors
  escape the tool and reach the refresh workflow, which deactivates the credential and disables
  its feeds — the same shape as `LlmClient::AuthError → disable_credential_on_auth_error`.
- Transient errors (429, 5xx, timeouts) stay in-band as `{ error: }` tool results for the model
  to retry or work around; no credential state change. A run whose gather comes back empty keeps
  recording the existing empty-gather event.

### 6. Usage tracking: counts now via events, cost later

No usage table and no `RateTable` mirror for now. Search pricing is flat per-query with no model
or token dimensions, so the LLM accounting machinery is the wrong shape; counting comes first and
cost estimation layers on later without schema work.

- **One debug-level Event per search API call**: subject = the search credential, user set, and an
  `EventReference` to the feed refresh event when the call happened inside a run.
- The feed refresh event surfaces its search-call count via that reference; the search credential
  page shows call counts per day/week/month.
- **All stats are time-scoped windows** (the `STATS_PERIOD` pattern). Never display all-time
  totals — events are subject to retention, so all-time numbers would silently shrink.
- Preview and validation searches record the same event without a feed-refresh reference; a
  reference-less event self-documents as "not a feed run".
- Cost estimation later = count × a per-query rate on the `WebSearchProvider::REGISTRY` entry,
  surfaced on the credential page and folded into time-scoped spend displays.
- **No per-run cap on search calls** — deliberate. Events keep the volume observable, and the
  user pays for both the LLM and the search key, so the incentive is self-limiting.

### 7. Preview parity

- The preview path receives the search credential the same way it receives the AI credential —
  passed explicitly, no dependence on a persisted feed.
- `search_credential_id` joins the preview digest alongside `ai_credential_id` / `ai_model`, so
  switching search credentials invalidates cached previews the same way switching AI credentials
  does.

### 8. Plumbing: tool context and seam deletion

- The `WebSearch` tool stops being a bare class registered via `with_tool(Class)`. Adapters
  instantiate it per run with the resolved credential and enough context (user, feed, refresh
  event) to emit the §6 events. This context injection is the real work inside "rewire the seam" —
  nothing else in the provider layer changes, since `WebSearchProvider.for(name, api_key:)`
  already takes the key as a parameter.
- Delete the interim ENV seam once credential resolution is live: `WebSearchProvider.default`,
  `.configured?`, `ENV_KEYS`, `env_key`, and the Moonshot adapter's `configured?` guard. No
  migration or deprecation window — there is no production deployment yet.

### 9. Wiring checklist

- `search_credential_deactivated` and the per-search event types get `EventDescriptionComponent`
  rendering and locale keys.
- Admin twins of the feed and event pages include search-call counts wherever they show LLM usage.
- CHANGELOG entry — this is user-facing, unlike #980.

## Sequencing

1. **Error taxonomy + tool context plumbing** (§5, §8) — foundational, independently landable:
   typed `AuthError`, per-run tool instantiation.
2. **`SearchCredential` model + validation job + management UI** (§1, §2).
3. **Feed FK + form section + gating + detours** (§4).
4. **Adapter unification on client-side search** (§3) + capability-matrix re-verification —
   depends on 2–3 so every enabled AI feed already carries a credential to resolve.
5. **Delete the ENV seam** (§8) — last, after nothing reads it.
6. **Events + usage surfaces** (§6, §9) — can land with or after 4.

## Open / deferred

- **Cost estimation** (§6) — deferred: per-query rates on registry entries, cost columns or
  derived display, spend fold-in on feed/event pages. Counting ships first.
- **Anthropic fetch path** (§3) — server-side `web_fetch` vs client-side tool; decided during
  adapter work with live verification.
- **A dedicated usage table** — only if cost tracking later outgrows event-based counting
  (e.g. needs outcome enums or finer retention than events allow).
- **Per-run search-call cap** — deliberately none (§6); revisit only if event data shows runaway
  volumes in practice.
