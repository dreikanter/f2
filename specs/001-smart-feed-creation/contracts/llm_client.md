# Contract: `LlmClient`

**Audience**: stage-class authors and the preview service.
**Status**: planning-time (Phase 1 design output).

`LlmClient` is the only entry point for AI calls. Stage classes never instantiate provider SDKs directly; they ask the client for a structured result and get back a value object.

## Construction

```ruby
LlmClient.for(feed)               # production: resolves user's default credential for the required provider
LlmClient.for(user, provider)     # bypass feed (used during preview when no Feed instance exists)
LlmClient.for(credential)         # explicit credential (used during credential validation)
```

All factory methods return an instance bound to one credential. Stage code never sees the provider name; it sees the client.

## Call

```ruby
result = client.call(
  feed:             Feed?,        # nil for preview / validation; sets LlmUsage.feed_id
  profile_key:      String,       # for LlmUsage.profile_key
  stage:            Symbol,       # :loader | :processor | :normalizer | :validation
  purpose:          Symbol,       # :scheduled_run (default) | :preview | :validation
  model:            String,       # e.g. "claude-opus-4-7"
  prompt:           String,       # rendered prompt (template substitution already applied)
  output_schema:    Hash,         # JSON Schema Draft 2020-12 for structured response
  tools:            Array<String> # provider-side server tool names; default []
)
```

Returns:

```ruby
LlmClient::Result.new(
  payload: Hash,                  # the structured output, validated against output_schema
  usage_id: Integer               # the LlmUsage row id written for this call
)
```

Raises (after writing the LlmUsage row with the appropriate `outcome`):

- `LlmClient::ProviderError` — network / 5xx / unrecognized error from the provider.
- `LlmClient::SchemaError` — provider returned a response that didn't validate against `output_schema`.
- `LlmClient::RateLimited` — provider 429; carries `retry_after` if available.
- `LlmClient::Timeout` — request exceeded the per-call deadline.

`LlmClient::Result` is the *only* shape that ever leaves the client. Stage classes pattern-match on `payload` keys defined by their `output_schema`.

## Behavior contract

1. **One HTTP request out, one response in.** No client-side tool loops. Provider-side server tools (web search, web fetch) execute inside the provider's response. If multi-step orchestration is needed in the future, it's a different stage shape (parent spec future scope: bounded LLM agents).
2. **Always writes one `LlmUsage` row.** Success or failure, the row gets written before the method returns or raises. The row carries the snapshot of `model`, `provider`, `purpose`, and outcome enum.
3. **Schema-validates output.** A response that doesn't match `output_schema` raises `SchemaError`; no malformed payload is ever returned to the caller.
4. **Reports unexpected errors.** Provider errors and timeouts go through `Rails.error.report` with `feed_id`, `profile_key`, `provider`, `model`, `stage`, `purpose` context. `SchemaError` and `RateLimited` are *expected* failures and use `Rails.error.handle` instead (already inside the client's `rescue` block).
5. **Adapts to provider via RubyLLM.** `LlmClient.call` invokes the `ruby_llm` gem directly with the profile's `output_schema`. Provider-specific dispatch (Anthropic forced tool use; OpenAI `response_format: json_schema`; Gemini equivalent) is RubyLLM's responsibility, not ours. `LlmClient` translates RubyLLM exceptions into its own hierarchy (`ProviderError` / `RateLimited` / `Timeout` / `SchemaError`) and pulls usage tokens (`input_tokens`, `output_tokens`, `cache_read_tokens` where applicable — e.g. Anthropic prompt-cache hits) from the RubyLLM response.
6. **Cost computation.** `LlmClient` reads raw token counts from the RubyLLM response, looks up the per-model rate from `config/llm_rates.yml` (loaded at boot), and writes `cost_estimate_cents` into the usage row. Rate-table changes never alter historical rows.
7. **Detection guard.** `LlmClient.call` raises `LlmClient::DetectionForbidden` if invoked from a thread / fiber tagged with `Thread.current[:llm_detection_phase] = true`. `FeedProfileDetector` sets and clears this flag. Belt-and-suspenders for FR-007 / SC-004.

## Health check

`LlmClient.for(credential).health_check` performs a cheap "are credentials usable" call (used by `LlmCredentialValidationJob`). Returns `true` on success; raises `ProviderError` otherwise. Writes one `LlmUsage` row per call with `feed_id: nil`, `stage: :validation`, `purpose: :validation`, `outcome: :success | :provider_error | :rate_limited | :timeout` — so the audit trail covers every validation attempt and its cost.

## Test contract

- `LlmClient` unit tests use `WebMock` (with RubyLLM driving HTTP) for end-to-end paths per provider that has a registered profile: success, schema violation, 429, 500, timeout. Assertions cover: usage row written on success and on each failure mode; schema validation fires; detection guard fires; Anthropic-specific prompt-cache token surfacing and `web_search` / `web_fetch` server tool pass-through.
- Stage tests stub `LlmClient.for(...)` to return a mock with prescripted `call` responses; they never touch RubyLLM directly.

## Migration notes

The first AI-using profile (`llm_website_extractor`) ships in the same task that introduces `LlmClient`. The client + first profile move together so the seam is exercised end-to-end immediately.
