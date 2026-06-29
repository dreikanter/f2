# LLM Provider Seam + Healing Implementation Plan (Track 2 of 6)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the `with_tool("web_search")` misuse with a thin per-provider seam that injects web access via `with_params` and heals OpenRouter's best-effort structured output, while `LlmClient` keeps owning selection, execution, usage, and the error taxonomy.

**Architecture:** Two pieces, cut by responsibility. `SchemaHealer` is a pure, provider-agnostic mechanism that recovers a JSON value from loose model text. `LlmClient::Adapter::{Anthropic,OpenRouter}` is a thin per-provider seam selected by `credential.provider`, owning `web_params(model)` (merged into the request via RubyLLM `with_params`) and `normalize(raw)` (passthrough for Anthropic's native enforcement; delegate to `SchemaHealer` for OpenRouter). `LlmClient#invoke_provider` routes through the adapter; structured output still goes through RubyLLM's `with_schema`.

**Tech Stack:** Ruby (mise), Rails edge, RubyLLM 1.16, JSONSchemer, Minitest + FactoryBot, RuboCop.

**Spec:** [`spec.md`](./spec.md) §6 (provider seam & healing).

## Global Constraints

- Run via mise: `bin/rails test`, `bin/rubocop -f github`. (My non-interactive shell needs `env -u GEM_HOME -u GEM_PATH -u RUBYLIB -u RUBYOPT -u BUNDLE_GEMFILE PATH="$HOME/.local/share/mise/shims:$PATH"` prefixed; a normal mise-activated shell does not.)
- Minitest + FactoryBot, lazy memoized helpers. Unit-test naming: `test "#method should ..."`.
- Trailing newline on every source file. RuboCop clean after each change.
- Report handled exceptions via `Rails.error.report(e, context: {...})`.
- **No planning/track references in code or comments** — they're irrelevant after merge. Keep this plan's track talk in this doc only.
- Atomic commits, imperative subjects ≤ 50 chars. No CHANGELOG entry (internal).

## File Structure

- `app/services/schema_healer.rb` — new (PR-2a). Pure: `SchemaHealer.call(raw) -> Hash | Array`, raises `SchemaHealer::Error`.
- `app/services/llm_client/adapter.rb` — new (PR-2b). `LlmClient::Adapter.for(provider)` factory.
- `app/services/llm_client/adapter/anthropic.rb` — new (PR-2b). `web_params(model)`, `normalize(raw)`.
- `app/services/llm_client/adapter/open_router.rb` — new (PR-2b). `web_params(model)`, `normalize(raw)` (heals).
- `app/services/llm_client.rb` — modify (PR-2b). Route `invoke_provider` through the adapter; drop `with_tool` and the `tools:` plumbing.
- `app/services/loader/llm_loader.rb` — modify (PR-2b). Stop passing `tools:` to `LlmClient#call`.

---

## PR-2a — `SchemaHealer`

### Task 1: `SchemaHealer`

**Files:**
- Create: `app/services/schema_healer.rb`
- Test: `test/services/schema_healer_test.rb`

**Interfaces:**
- Produces: `SchemaHealer.call(raw) -> Hash | Array`. Accepts a `Hash`/`Array` (returned as-is) or a `String`. Parses strict JSON; on failure strips Markdown code fences and extracts the outermost `{...}`/`[...]` span and parses that. Raises `SchemaHealer::Error` when no JSON value is recoverable.

- [ ] **Step 1: Write the failing test**

Create `test/services/schema_healer_test.rb`:

```ruby
require "test_helper"

class SchemaHealerTest < ActiveSupport::TestCase
  test "#call should pass a Hash through unchanged" do
    assert_equal({ "items" => [] }, SchemaHealer.call({ "items" => [] }))
  end

  test "#call should parse a plain JSON object string" do
    assert_equal({ "a" => 1 }, SchemaHealer.call('{"a":1}'))
  end

  test "#call should parse a top-level JSON array" do
    assert_equal [1, 2], SchemaHealer.call("[1, 2]")
  end

  test "#call should strip a fenced json code block" do
    raw = "```json\n{\"a\": 1}\n```"
    assert_equal({ "a" => 1 }, SchemaHealer.call(raw))
  end

  test "#call should strip a bare fenced code block" do
    raw = "```\n{\"a\": 1}\n```"
    assert_equal({ "a" => 1 }, SchemaHealer.call(raw))
  end

  test "#call should extract an object embedded in prose" do
    raw = %(Here are the results: {"a": 1, "b": [2, 3]} — hope that helps!)
    assert_equal({ "a" => 1, "b" => [2, 3] }, SchemaHealer.call(raw))
  end

  test "#call should raise when there is no recoverable JSON" do
    assert_raises(SchemaHealer::Error) { SchemaHealer.call("I could not complete this request.") }
  end

  test "#call should raise on blank input" do
    assert_raises(SchemaHealer::Error) { SchemaHealer.call("") }
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/schema_healer_test.rb`
Expected: FAIL — `NameError: uninitialized constant SchemaHealer`.

- [ ] **Step 3: Write minimal implementation**

Create `app/services/schema_healer.rb`:

```ruby
# Recovers a JSON value from loose model output. Providers that don't enforce
# structured output natively can wrap JSON in Markdown fences or surrounding
# prose; this strips that noise and parses the outermost JSON span. It does not
# repair invalid JSON or reshape against a schema — shape validation stays with
# the caller. Raises when nothing parseable is present.
class SchemaHealer
  Error = Class.new(StandardError)

  FENCE = /```(?:json)?\s*(.+?)```/m

  def self.call(raw)
    return raw if raw.is_a?(Hash) || raw.is_a?(Array)

    text = raw.to_s
    JSON.parse(text)
  rescue JSON::ParserError
    embedded(text) || raise(Error, "no recoverable JSON in response")
  end

  def self.embedded(text)
    source = text[FENCE, 1] || text
    open_at = source.index(/[\[{]/)
    close_at = source.rindex(/[\]}]/)
    return if open_at.nil? || close_at.nil? || close_at <= open_at

    JSON.parse(source[open_at..close_at])
  rescue JSON::ParserError
    nil
  end

  private_class_method :embedded
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/schema_healer_test.rb`
Expected: PASS (8 runs, 0 failures).

- [ ] **Step 5: Lint**

Run: `bin/rubocop -f github app/services/schema_healer.rb test/services/schema_healer_test.rb`
Expected: no offenses.

- [ ] **Step 6: Commit**

```bash
git add app/services/schema_healer.rb test/services/schema_healer_test.rb
git commit -m "Add SchemaHealer for loose JSON recovery"
```

PR-2a is a complete, mergeable unit: a pure service with no caller yet.

---

## PR-2b — Per-provider seam + routing

> **Verification ceiling — read before implementing.** The *exact* `web_params` wire formats and the real "web + schema together" behavior can only be confirmed against the live provider APIs with credentials. The unit tests below assert the seam's **behavior** (selection, that `LlmClient` injects `web_params` via `with_params`, that `normalize` heals only for OpenRouter) by stubbing the chat — they do **not** assert provider wire correctness. Treat the literal `web_params` hashes as best-effort defaults to confirm against provider docs + a live smoke run before relying on them. Items needing live confirmation are tagged **[VERIFY-LIVE]**.

### Task 2: Adapter interface + factory + Anthropic adapter

**Files:**
- Create: `app/services/llm_client/adapter.rb`, `app/services/llm_client/adapter/anthropic.rb`
- Test: `test/services/llm_client/adapter_test.rb`

**Interfaces:**
- Produces: `LlmClient::Adapter.for(provider) -> adapter`. Each adapter responds to `web_params(model) -> Hash` (params to merge via `with_params`) and `normalize(raw) -> Hash | Array` (raising `LlmClient::SchemaError` when unrecoverable).
- Consumes: `SchemaHealer.call` (OpenRouter adapter, Task 3).

- [ ] **Step 1: Write the failing test**

Create `test/services/llm_client/adapter_test.rb`:

```ruby
require "test_helper"

class LlmClient::AdapterTest < ActiveSupport::TestCase
  test ".for should return the Anthropic adapter" do
    assert_instance_of LlmClient::Adapter::Anthropic, LlmClient::Adapter.for("anthropic")
  end

  test ".for should raise for an unknown provider" do
    assert_raises(KeyError) { LlmClient::Adapter.for("nope") }
  end

  test "anthropic #web_params should declare web search and fetch server tools" do
    params = LlmClient::Adapter::Anthropic.new.web_params("claude-opus-4-8")

    tool_types = params.fetch(:tools).map { |t| t[:type] }
    assert_includes tool_types, "web_search_20260209"
    assert_includes tool_types, "web_fetch_20260209"
  end

  test "anthropic #normalize should pass a Hash through and trust native output" do
    adapter = LlmClient::Adapter::Anthropic.new
    assert_equal({ "items" => [] }, adapter.normalize({ "items" => [] }))
    assert_equal({ "a" => 1 }, adapter.normalize('{"a":1}'))
  end

  test "anthropic #normalize should raise SchemaError on non-JSON" do
    assert_raises(LlmClient::SchemaError) { LlmClient::Adapter::Anthropic.new.normalize("nope") }
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/llm_client/adapter_test.rb`
Expected: FAIL — `uninitialized constant LlmClient::Adapter`.

- [ ] **Step 3: Write the factory + Anthropic adapter**

Create `app/services/llm_client/adapter.rb`:

```ruby
class LlmClient
  # Per-provider seam for the two things RubyLLM does not normalize: enabling
  # web access on the request, and recovering usable output from providers that
  # don't enforce structured output natively. Structured output itself still
  # goes through RubyLLM's `with_schema`.
  module Adapter
    REGISTRY = {
      "anthropic" => Anthropic,
      "openrouter" => OpenRouter
    }.freeze

    def self.for(provider)
      REGISTRY.fetch(provider.to_s).new
    end
  end
end
```

> Note: Ruby resolves `Anthropic`/`OpenRouter` in the literal above only if the autoloader has loaded them. With Zeitwerk this is fine at call time; if a load-order error appears, reference them as strings and `constantize` in `.for`.

Create `app/services/llm_client/adapter/anthropic.rb`:

```ruby
class LlmClient
  module Adapter
    # Anthropic enforces structured output natively, so `normalize` trusts the
    # payload. Web access is the provider-hosted search/fetch server tools.
    class Anthropic
      # [VERIFY-LIVE] tool type versions are model-gated; confirm these are the
      # variants the supported models accept, and that citations-off is required
      # alongside a schema.
      def web_params(_model)
        {
          tools: [
            { type: "web_search_20260209", name: "web_search" },
            { type: "web_fetch_20260209", name: "web_fetch", citations: { enabled: false } }
          ]
        }
      end

      def normalize(raw)
        return raw if raw.is_a?(Hash) || raw.is_a?(Array)

        JSON.parse(raw.to_s)
      rescue JSON::ParserError => e
        raise LlmClient::SchemaError, "non-JSON response from provider: #{e.message}"
      end
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/llm_client/adapter_test.rb`
Expected: PASS.

- [ ] **Step 5: Lint, then commit**

```bash
bin/rubocop -f github app/services/llm_client/adapter.rb app/services/llm_client/adapter/anthropic.rb test/services/llm_client/adapter_test.rb
git add app/services/llm_client/adapter.rb app/services/llm_client/adapter/anthropic.rb test/services/llm_client/adapter_test.rb
git commit -m "Add LLM provider adapter seam with Anthropic adapter"
```

### Task 3: OpenRouter adapter (heals)

**Files:**
- Create: `app/services/llm_client/adapter/open_router.rb`
- Test: extend `test/services/llm_client/adapter_test.rb`

**Interfaces:**
- Consumes: `SchemaHealer.call` (PR-2a).

- [ ] **Step 1: Add failing tests**

Append to `test/services/llm_client/adapter_test.rb`:

```ruby
  test ".for should return the OpenRouter adapter" do
    assert_instance_of LlmClient::Adapter::OpenRouter, LlmClient::Adapter.for("openrouter")
  end

  test "openrouter #web_params should enable the web server tool and require parameters" do
    params = LlmClient::Adapter::OpenRouter.new.web_params("anthropic/claude-opus-4-8")

    assert params.key?(:plugins) || params.dig(:provider, :require_parameters),
           "expected web plugin and/or require_parameters to be set"
  end

  test "openrouter #normalize should heal fenced JSON" do
    healed = LlmClient::Adapter::OpenRouter.new.normalize("```json\n{\"items\": []}\n```")
    assert_equal({ "items" => [] }, healed)
  end

  test "openrouter #normalize should raise SchemaError when unhealable" do
    assert_raises(LlmClient::SchemaError) { LlmClient::Adapter::OpenRouter.new.normalize("sorry, no json") }
  end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/services/llm_client/adapter_test.rb`
Expected: FAIL — `uninitialized constant LlmClient::Adapter::OpenRouter`.

- [ ] **Step 3: Implement the OpenRouter adapter**

Create `app/services/llm_client/adapter/open_router.rb`:

```ruby
class LlmClient
  module Adapter
    # OpenRouter routes across upstreams and enforces structured output only
    # best-effort, so `normalize` heals the response. Web access is OpenRouter's
    # cross-model web server tool.
    class OpenRouter
      # [VERIFY-LIVE] confirm the current web-access wire format (server tool vs
      # the deprecated `web` plugin) and that require_parameters routes only to
      # upstreams honoring response_format.
      def web_params(_model)
        {
          plugins: [{ id: "web" }],
          provider: { require_parameters: true }
        }
      end

      def normalize(raw)
        SchemaHealer.call(raw)
      rescue SchemaHealer::Error => e
        raise LlmClient::SchemaError, e.message
      end
    end
  end
end
```

- [ ] **Step 4: Run to verify pass, then lint + commit**

```bash
bin/rails test test/services/llm_client/adapter_test.rb
bin/rubocop -f github app/services/llm_client/adapter/open_router.rb test/services/llm_client/adapter_test.rb
git add app/services/llm_client/adapter/open_router.rb test/services/llm_client/adapter_test.rb
git commit -m "Add OpenRouter adapter with response healing"
```

### Task 4: Route `LlmClient` through the adapter; drop `with_tool`

**Files:**
- Modify: `app/services/llm_client.rb` (`invoke_provider`, `parse_payload`, `call` signature)
- Modify: `app/services/loader/llm_loader.rb` (stop passing `tools:`)
- Test: `test/services/llm_client_test.rb` (existing — adjust the seam stub)

**Interfaces:**
- Consumes: `LlmClient::Adapter.for`, adapter `web_params`/`normalize`.
- Produces: `LlmClient#call(ctx, prompt:, output_schema:)` — the `tools:` keyword is removed.

- [ ] **Step 1: Read the existing LlmClient seam test**

Run: `sed -n '1,60p' test/services/llm_client_test.rb` to see how `invoke_provider`/`fetch_provider_models` are stubbed. The existing tests stub `invoke_provider` to return a `ProviderResponse`; those keep working. Add one test asserting `web_params` is injected and `normalize` is used. **[VERIFY-LIVE]** the precise `with_params` call shape against RubyLLM.

- [ ] **Step 2: Update `invoke_provider`**

In `app/services/llm_client.rb`, replace the body of `invoke_provider` (currently lines ~147-160). Remove the `tools` parameter and the `tools.each { |t| chat.with_tool(t) }` line. New version:

```ruby
  def invoke_provider(model:, prompt:, output_schema:)
    adapter = Adapter.for(credential.provider)
    chat = credential.ruby_llm_context.chat(model: model, provider: LlmProvider.find(credential.provider).ruby_llm_provider)
    chat.with_schema(output_schema) if output_schema.present? && chat.respond_to?(:with_schema)
    chat.with_params(**adapter.web_params(model)) if chat.respond_to?(:with_params)

    response = chat.ask(prompt)
    ProviderResponse.new(
      payload: adapter.normalize(response.respond_to?(:content) ? response.content : response),
      input_tokens: response.try(:input_tokens).to_i,
      output_tokens: response.try(:output_tokens).to_i,
      cache_write_tokens: response.try(:cached_tokens).to_i,
      cache_read_tokens: response.try(:cache_read_tokens).to_i
    )
  end
```

Delete the now-unused `parse_payload` method (its job moved into `adapter.normalize`).

- [ ] **Step 3: Update `call` signature**

Remove `tools: []` from `def call(ctx, prompt:, output_schema:, tools: [])` and from the `invoke_provider(...)` call inside it.

- [ ] **Step 4: Update `LlmLoader`**

In `app/services/loader/llm_loader.rb`, drop `tools: config.fetch(:tools, [])` from the `llm_client.call(...)` arguments. (The profile's `tools` config key is now unread; it is cleaned up in the profile-collapse work.)

- [ ] **Step 5: Run the LlmClient + loader tests**

Run: `bin/rails test test/services/llm_client_test.rb test/services/loader/llm_loader_test.rb`
Expected: PASS (adjust any test that passed `tools:` or asserted `with_tool`).

- [ ] **Step 6: Full suite + lint**

Run: `bin/rails test` (expect green) and `bin/rubocop -f github app/services/llm_client.rb app/services/loader/llm_loader.rb`.

- [ ] **Step 7: Commit**

```bash
git add app/services/llm_client.rb app/services/loader/llm_loader.rb test/services/llm_client_test.rb
git commit -m "Route LLM calls through the provider adapter"
```

---

## Self-Review

- **Spec coverage (§6):** `SchemaHealer` provider-agnostic ✓ (Task 1); per-provider seam selected by provider ✓ (Task 2); Anthropic native trust + web server tools ✓ (Task 2); OpenRouter heal + web access ✓ (Task 3); `with_tool` misuse removed, structured output stays in `with_schema`, `LlmClient` keeps selection/execution/usage/error-taxonomy ✓ (Task 4). Anthropic `pause_turn`/server-tool-loop handling is **[VERIFY-LIVE]** and tracked as a follow-up once a live smoke run is possible.
- **Placeholders:** none in PR-2a. PR-2b's `web_params` hashes are explicit but tagged **[VERIFY-LIVE]** — confirm against provider docs + a credentialed smoke run before trusting the wire formats.
- **Type consistency:** `SchemaHealer.call -> Hash|Array` raising `SchemaHealer::Error`; adapters' `normalize -> Hash|Array` raising `LlmClient::SchemaError`; `web_params -> Hash` merged via `with_params`. `LlmClient#call` loses `tools:`; `LlmLoader` stops passing it.
