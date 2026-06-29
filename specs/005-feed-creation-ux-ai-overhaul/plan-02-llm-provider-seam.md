# LLM Provider Seam Implementation Plan (Track 2 of 6)

**Goal:** Give `LlmClient` a thin per-provider seam that enables web access via `with_params`, and remove the `with_tool("web_search")` misuse.

**Scope note:** An earlier draft of this plan added a `SchemaHealer` for loose JSON recovery. It was **dropped as speculative** — RubyLLM enforces structured output through both providers (`with_schema`), Anthropic does so natively, and the dev-verified matrix (§5) excludes OpenRouter models that don't return clean JSON. The required behaviour is parse-or-fail, which `LlmClient` already does. Revisit only if a verified model is observed wrapping its output. See spec §6.

**Spec:** [`spec.md`](./spec.md) §6.

## What shipped (one PR)

- `LlmClient::Adapter.for(provider)` — factory keyed on `credential.provider`, raises `KeyError` for unknown providers.
- `LlmClient::Adapter::Anthropic#web_params(model)` — provider-hosted `web_search`/`web_fetch` server tools, citations disabled.
- `LlmClient::Adapter::OpenRouter#web_params(model)` — web plugin + `require_parameters`.
- `LlmClient#invoke_provider` — injects `web_params` via `chat.with_params`; structured output still goes through `chat.with_schema`. The `with_tool` loop is gone; `tools:` removed from `#call`.
- `Loader::LlmLoader` — stops passing `tools:`.

`web_params` wire-format values are `[VERIFY-LIVE]`: the injection mechanism is verified against the RubyLLM source (`with_params` deep-merges into the request payload), but the exact provider strings (Anthropic tool versions, OpenRouter web mechanism) need a credentialed smoke run to confirm.

## Verified mechanism

- `Chat#with_params` sets `@params`, deep-merged into the rendered payload (`provider.rb` `Utils.deep_merge(render_payload(...), params)`). With no function tools, injecting `tools:`/`plugins:` lands cleanly alongside the schema's `output_config`.
- RubyLLM 1.16 renders Anthropic structured output as the current `output_config.format` / `json_schema` (`providers/anthropic/chat.rb`). The adapter does not own schema injection.

## Tests

- `test/services/llm_client/adapter_test.rb` — factory selection (incl. symbol provider, unknown → `KeyError`) and each adapter's `web_params` shape.
- Existing `llm_client_test` / `llm_loader_test` pass unchanged (they never used `tools:`).

## Deferred / [VERIFY-LIVE]

- Confirm Anthropic web tool-version strings and that citations-off is required with a schema.
- Confirm OpenRouter's live web mechanism (web plugin vs `openrouter:web_search` server tool) and `require_parameters` routing.
- Anthropic `pause_turn` / server-tool-loop handling.
