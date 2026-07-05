# LLM Provider Capability Verification (Track 3 of the AI work)

**Date**: 2026-07-05 | **Status**: Findings record

Live-verification of which providers/models can deliver the three capabilities the AI engine
needs — **web fetch**, **web search**, **structured output** — *through RubyLLM* (1.16). Answers
[spec §5](./spec.md) (matrix membership = qualification) and revisits [§6](./spec.md) (two-step vs
combined) with hard evidence rather than docs or prior model knowledge.

Verification tooling shipped in #914: `LlmCapabilityProbe` + per-provider probe jobs, and the
`KimiExperiment` focused experiments, all run from the dev-area jobs runner (issue #915) with results
recorded as `JobRun` events. Runs below were executed on staging against live keys.

## Verdicts

| Provider / model | Fetch | Search | Structured output | Verdict |
|---|---|---|---|---|
| Anthropic `claude-sonnet-4-6` | ✅ server tool | ✅ server tool | ✅ strict, clean | **Qualified** — and schema+web work *combined* in one call |
| Moonshot `kimi-k2.5` | ✅ via client tool | ⚠️ needs external search API | ⚠️ fences ~⅔ of the time | **Qualified for fetch-only feeds**, with caveats below |
| OpenRouter | — | — | — | **Dropped** (not payable; removed from scope) |

## Anthropic — qualified, and simpler than §6 assumed

All six probe checks passed on Sonnet (plain, schema, web_search, web_fetch, two_step, **combined**).
The load-bearing finding: the **combined** check (schema + web in one RubyLLM call) returned grounded,
schema-valid items citing real current rubyonrails.org posts — the same posts the standalone
web_search check found.

§6 built the two-step (gather → structure) design on "schema + web breaks through RubyLLM." That is
**no longer true for Anthropic through RubyLLM 1.16** — combined works. So for Anthropic the engine can
collapse to a single call: cheaper (one usage row, no gathered-text re-feed), faster (~43s vs ~60s
observed), and no intermediate text to lose fidelity through. Two-step remains a valid *fallback shape*
the seam still supports, but it is no longer the required default.

(Incidental confirmation of §3: the combined step minted uids `"1"`/`"2"` while two-step echoed
permalinks — model-supplied uids are not trustworthy, exactly why the processor mints them.)

## Moonshot / Kimi — the interesting case

Kimi's token price is the motivation (a cheap provider for staging and less-critical feeds). The
experiments (`KimiWebSearchWireJob`, `KimiStructuredOutputJob`, `KimiClientToolJob`) establish exactly
what works and what doesn't:

- **Built-in `$web_search` does not engage.** Auto: HTTP 200 but the model imitated the tool as *plain
  text* (```` ```web_search\nquery: … ```` inside `content`, `finish_reason=stop`, no real tool call) —
  the server never ran a search. Forced (`tool_choice`): HTTP 400,
  *"tool_choice 'specified' is incompatible with thinking enabled."* Moonshot's server-side search is
  not usable through the API as configured.
- **Structured output is unreliable.** Even with `response_format: json_schema`, output arrived
  markdown-fenced (```` ```json ````) ~⅔ of runs (none 0/3 clean, json_object 1/3, json_schema 1/3).
  Strict native JSON cannot be assumed.
- **Client-side function tools work.** A fixed-URL fetch tool handed to Kimi through RubyLLM's tool
  loop was invoked correctly and produced **genuinely grounded** output — the real current Rails blog
  posts with correct URLs. This is the viable path.
- Model quirk: `kimi-k2.5` rejects any `temperature` other than `1` (400 otherwise). RubyLLM's per-model
  temperature normalization handles this; raw callers must pin it.

### What a Kimi integration requires

Kimi is usable **if we stop relying on Moonshot's builtins** and instead:

1. **Bring our own retrieval as client-side tools.** Two separable capabilities:
   - **Fetch** (URL → content): a hardened HTTP GET, machinery the app already has. **No new
     dependency.** Proven working.
   - **Search** (query → candidate URLs): requires an **external search API** (Brave / Tavily / SerpAPI
     / Bing …) wrapped as a function tool — a new dependency, key, and cost. Not yet integrated.
2. **Tolerate fenced JSON on the structure step** — a single deterministic `unfence` string operation
   (strip a leading ```` ```json ```` / trailing ```` ``` ````), *not* LLM-based healing. This is a
   narrow, provider-scoped exception to §6's strict no-heal rule, justified by the evidence.

### The fetch/search split maps onto the feed regimes

- **Fetch-only feeds** (a known source — Mode A-style "follow this blog"): Kimi works **today**, zero
  new dependencies.
- **Search-driven feeds** (open-ended discovery — the standing-query/digest regime, §3): Kimi needs an
  external search-API tool; Anthropic gets this built-in.

**Recommendation:** scope Kimi to **fetch-only feeds first** — an immediate cheap-provider win with no
new infrastructure — and treat search-API integration as a separate, later decision made only once
staging actually needs discovery feeds on Kimi.

## Consequences for the spec

- §5 matrix: Anthropic Sonnet qualified; Kimi qualified for fetch-only; OpenRouter dropped. Membership
  is per-**capability-set**, not a single flag — a provider can qualify for fetch-and-structure without
  qualifying for search.
- §6: the "never combine schema+web" premise is Anthropic-specific *and now stale for Anthropic through
  RubyLLM 1.16*. The per-provider seam is doing exactly the job it was designed for — retrieval
  mechanism and structured-output handling now differ by provider (Anthropic: server tools + combined
  call; Kimi: client tools + de-fenced structure).

## Deferred

- External search-API selection and the search function tool (only if discovery feeds on a cheap
  provider are wanted).
- Whether to switch Anthropic extraction from two-step to combined in production (net win; own change).
- Kimi `unfence` + client-fetch tool promoted from experiment code into the real adapter, once the
  above scope is chosen.
