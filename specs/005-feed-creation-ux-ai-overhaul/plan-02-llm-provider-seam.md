# LLM Provider Seam + Two-Step Extraction Plan (Track 2 of 6)

**Goal:** Make AI extraction work through RubyLLM by splitting it into two calls — gather (web, no schema) then structure (schema, no web) — and give `LlmClient` a per-provider web-params seam plus a `web:` flag.

**Spec:** [`spec.md`](./spec.md) §6.

## Why two steps (live findings)

Verified against real Anthropic calls:

- Schema + web tools in **one** call works at the raw API (HTTP 200, clean JSON) but **breaks through RubyLLM** — RubyLLM has no server-tool handling and mishandles the web tool once a schema is set.
- Web alone and schema alone each work cleanly through RubyLLM.
- We keep RubyLLM (no raw per-provider clients), so extraction is two calls that never combine the two.

## What shipped

- **`LlmClient::Adapter`** — `for(provider)` factory; `Anthropic`/`OpenRouter` each expose `web_params(model) -> Hash`. Anthropic: `web_search_20260209`/`web_fetch_20260209` server tools, citations off. OpenRouter: web plugin + `require_parameters`.
- **`LlmClient#call(ctx, prompt:, output_schema:, web:)`** — injects `web_params` via `with_params` only when `web: true`; returns raw text when `output_schema` is nil, parsed+validated JSON when a schema is given. Keeps usage bookkeeping (one row per call), error taxonomy, adapter selection. `with_tool` misuse removed.
- **`Loader::LlmLoader`** — two calls: gather (`web: true`, no schema) → structure (schema, `web: false`, gathered text fed in). Returns `items`.
- **`UNIVERSAL_OUTPUT_SCHEMA`** — `additionalProperties: false` on every object (Anthropic strict requirement, confirmed live).

## Tests

- `test/services/llm_client/adapter_test.rb` — factory + `web_params` shape.
- `test/services/loader/llm_loader_test.rb` — two-call order (gather web/no-schema, then structure schema/no-web), gathered text feeds the structuring prompt, limit, missing-items raise, model resolution.
- `LlmClient`'s `web:`/no-schema-text internals are exercised at the loader seam and proven by live scripts; not separately unit-stubbed (tests deliberately stub at `invoke_provider`, away from RubyLLM).

## Deferred / [VERIFY-LIVE]

- OpenRouter web mechanism + `require_parameters` — not yet run live.
- Gather/structure prompts are functional placeholders — Track 4 owns the final prompts + system-prompt safeguards.
- Structure step is a Haiku cost-optimization candidate (separate model per step).
- Anthropic `pause_turn` handling is moot in the two-step path (gather returns `end_turn`); revisit only if a gather run pauses.
