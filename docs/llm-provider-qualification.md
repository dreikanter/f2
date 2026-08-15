# Qualifying an LLM provider or model

`LlmModelCapability` is an allowlist of `(provider, model)` pairs the AI engine
may use, and **membership is qualification**: a pair goes in only after a live
probe run shows it works on the shape production actually calls. The model
picker offers that list intersected with the credential's own model snapshot, so
an unqualified model can never be selected and fail asynchronously mid-run.

The probe (`LlmCapabilityProbe`) is the gate. It runs against the real provider
API — never recorded cassettes, because the question is live third-party
behavior — and it stays independent of managed credentials, so a provider can be
qualified before it is wired into the app at all.

## Running it

Keys come from the environment: `ANTHROPIC_API_KEY`, `MOONSHOT_API_KEY`
(`MOONSHOT_API_BASE` overrides the endpoint). Without a key the run records a
skip event and ends.

From the dev area — the usual path, and the one that keeps the evidence:

1. Set the key on the target environment (staging; see
   [deployment-setup.md](deployment-setup.md)).
2. Open `/development/jobs`, run `KimiCapabilityProbeJob` or
   `AnthropicCapabilityProbeJob`, and read the run under `job_runs`.

Each check writes one event with its full evidence — the models listing, the
tool calls with their arguments and results, the returned payload — so there is
no separate transcript to chase.

For a one-off pair, or a subset of checks, use the CLI instead:

```sh
bundle exec ruby script/llm_capability_probe.rb --provider moonshot --model kimi-k3
bundle exec ruby script/llm_capability_probe.rb --provider anthropic --model claude-sonnet-4-6 --checks models,client_tools
```

## What it checks, and why only these

Every check mirrors something a feed run does. Provider-hosted retrieval is
deliberately **not** probed: every provider retrieves through our own
client-side tools (`LlmClient::Adapter::Base#apply_web`), so whether a model's
own web search works tells us nothing about a feed.

| Check | What it proves |
| --- | --- |
| `models` | The id is served verbatim by the provider's listing — the allowlist matches on exact string |
| `plain` | Basic round trip |
| `system_prompt` | The system channel arrives and is obeyed; instructions contradict the obvious answer, so a dropped or rejected prompt fails |
| `schema` | Strict-schema JSON, repaired the way production repairs it (`Adapter#unwrap_json`) |
| `client_tools` | The model drives our search and fetch tools through a real multi-round loop and grounds its answer in fetched content — production's gather step |
| `client_tools_schema` | Schema and tools survive the *same* call — production's combined shape |

Two results need interpretation rather than a pass/fail reading:

- **`client_tools_schema` failing is not disqualifying.** It means the pair needs
  two-step extraction: gather with tools, then structure in a second call. That
  is what `LlmClient::Adapter#combined_extraction?` selects, and it is why
  Moonshot uses two calls where Anthropic uses one.
- **The run-level `passed` flag is a summary, not a verdict.** Read the checks.

Grounding is judged on what the tools returned, not on what the model says: the
expected page heading appears in neither the prompt nor the canned search
results, so an answer can only contain it via a fetch that really happened. A
schema-valid payload whose content is a refusal fails too.

## Adding a pair

1. Run the probe against the pair and confirm `models`, `system_prompt`,
   `schema` and `client_tools` pass.
2. Add the row to `LlmModelCapability::ENTRIES`, with the verification noted in
   the comment above it.
3. Add a rates entry in `config/llm_rates.yml`, verified against the provider's
   published pricing — costs shown to users come from it.
4. If the pair becomes a provider's default, `LlmProvider#default_model` moves
   too; an invariant test requires every provider's default to be in the matrix.

Re-run the probe when the production call shape changes, not just when adding a
pair. Pinning system prompts to role `system` for Moonshot invalidated the
earlier Kimi evidence, and that gap is exactly how a wire-format bug reached
production.

## Adding a provider

Before a pair can be probed, the provider needs:

- an `LlmProvider` entry (RubyLLM provider key, default model, API base if it
  rides another provider's adapter);
- an `LlmClient::Adapter` subclass, if it needs response repair or one-call
  extraction;
- a `LlmCapabilityProbe::Provider` subclass with `env_key`, `configure` and
  `ruby_llm_provider`, registered in that class's `REGISTRY`.

The probe's `configure` must mirror production's `LlmProvider#configure`. If
they drift, the probe qualifies a wire shape the app never sends.

A provider with no matrix rows is simply not selectable for AI feeds, which is
why an unqualified or unpayable provider can sit in the registry harmlessly.
