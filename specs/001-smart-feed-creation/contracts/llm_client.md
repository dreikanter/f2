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
5. **Adapts to provider.** The `LlmClient::Anthropic` adapter implements forced tool use (declare a tool whose `input_schema` is `output_schema`, set `tool_choice: {type: "tool", name: ...}`, return the tool's `input` as `payload`). Future `LlmClient::OpenAI` adapter uses `response_format: {type: "json_schema", ...}`. Adapters MUST surface usage tokens (`input_tokens`, `output_tokens`, `cache_read_tokens` where applicable) for `LlmUsage`.
6. **Cost computation.** Adapters return raw token counts; `LlmClient` looks up the per-model rate from `config/llm_rates.yml` (loaded at boot) and writes `cost_estimate_cents` into the usage row. Rate-table changes never alter historical rows.
7. **Detection guard.** `LlmClient.call` raises `LlmClient::DetectionForbidden` if invoked from a thread / fiber tagged with `Thread.current[:llm_detection_phase] = true`. `FeedProfileDetector` sets and clears this flag. Belt-and-suspenders for FR-007 / SC-004.

## Provider adapter interface

Each `LlmClient::<Provider>` adapter implements:

```ruby
def call(model:, prompt:, output_schema:, tools:, deadline:)
  # → AdapterResponse.new(payload: Hash, input_tokens:, output_tokens:, cache_read_tokens:)
  # raises ProviderError, RateLimited, Timeout, SchemaError
end

def health_check
  # cheap "are credentials usable" call; used by LlmCredentialValidationJob
  # → true | raises ProviderError
end
```

Adapters do not write `LlmUsage`; the top-level `LlmClient` does (so the schema/usage-row write is one place).

## Test contract

- `LlmClient` unit tests use `Minitest::Mock` to stub the adapter; they assert: usage row written on success and on each failure mode; schema validation runs; detection guard fires.
- `LlmClient::Anthropic` adapter tests use `WebMock` with fixture responses: success path, schema-violation path, 429 path, 500 path, timeout path.
- Stage tests stub `LlmClient.for(...)` to return a mock with prescripted `call` responses; they never touch the adapter.

## Migration notes

The first AI-using profile (`llm_website_extractor`) ships in the same task that introduces `LlmClient::Anthropic`. The client + adapter + first profile move together so the seam is exercised end-to-end immediately.
