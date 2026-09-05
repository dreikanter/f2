# Qualifying an LLM provider or model

## Free staging discovery report

Use this report to inspect model discovery before changing model selection.
It lists the models and metadata returned by the application's existing
`LlmClient` serialization. Some fields come from the SDK registry; their presence
does not prove runtime compatibility. Providers using `assume_model_exists`
currently expose only IDs and names in that serialization, so missing capability
metadata is expected.

1. Deploy the PR branch before merging: in GitHub Actions, choose **Deploy
   Staging**, select the PR branch under **Use workflow from**, and run it with
   bootstrap disabled. Wait for deployment to finish.
2. Sign in to staging with a developer account and open
   `/development/jobs/AiModelDiscoveryReportJob/job_runs`.
3. Click **Run**, refresh the list, and open the finished run. Click **Copy
   details** beside its JSON report and share that text.

The report uses the oldest active staging credential for each configured
provider, regardless of owner or display name. Providers without an active
credential are marked `SKIP`. It performs free model-listing requests only and
leaves credentials, model snapshots, and feeds unchanged. It never generates
content, searches, or publishes posts.

The report includes the deployed revision, SDK version, model lists, and each
listing's outcome. Provider error text is omitted because it can contain
credentials. A completed job means the report was generated; inspect each
provider's `PASS`, `FAIL`, or `SKIP` result. No result approves a model for use.

Paid capability probes below are separate actions. Run them only for a specific
integration question with bounded costs; model discovery does not require them.

## Model qualification

`LlmModelCapability` is an allowlist of `(provider, model)` pairs the AI engine
may use, and **membership is qualification**: a pair goes in only after a live
probe run shows it works on the shape production actually calls. The model
picker offers that list intersected with the credential's own model snapshot, so
an unqualified model can never be selected and fail asynchronously mid-run.

`LlmCapabilityProbe` is the gate. It runs against the real provider API on a
managed credential, through the same provider configuration a feed run uses
(`AiCredential#chat`), so a pass cannot come from a setup production doesn't
share.

## Running it

The key comes from the `AiCredential` named after the probe job, minus the `Job`
suffix — **AnthropicCapabilityProbe**, **KimiCapabilityProbe**,
**OpenAiCapabilityProbe** — on **your own account**. The dev area passes
whoever pressed Run through to the job, so a probe only ever spends its own
operator's tokens. Without that record the run records a skip saying which
credential to create.

From the dev area — the usual path, and the one that keeps the evidence
searchable afterwards:

1. Add an AI credential for the provider, named exactly as above.
2. Open `/development/jobs`, run the probe job for the pair
   (`AnthropicCapabilityProbeJob`, `KimiCapabilityProbeJob`,
   `OpenAiCapabilityProbeJob`), and read the run under `job_runs`.

Each check writes one event with its full evidence — the models listing, the
tool calls with their arguments and results, the returned payload — so there is
no separate transcript to chase.

For a one-off pair, or a subset of checks, use the CLI instead. It has no
session to read an operator from, so name one:

```sh
bundle exec ruby script/llm_capability_probe.rb --user me@example.com --job KimiCapabilityProbeJob --model kimi-k3
bundle exec ruby script/llm_capability_probe.rb --user me@example.com --job AnthropicCapabilityProbeJob --checks models
```

A provider must be in `LlmProvider`'s registry before it can be probed, since
that is what a credential is created against. Registering one exposes nothing on
its own: the model picker reads `LlmModelCapability`, which is what a passing
probe run earns.

Probe runs write no `LlmUsage` rows. Usage is feed-run accounting — its
`purpose` enum has no probe value and its rows hang off a feed — so probe cost
is reported in the run's own events instead of the credential's usage surface.

## What it checks, and why only these

Every check mirrors something a feed run does. Provider-hosted retrieval is
deliberately **not** probed: every provider retrieves through our own
client-side tools (`LlmClient::Adapter::Base#apply_web`), so whether a model's
own web search works tells us nothing about a feed.

| Check | What it proves |
| --- | --- |
| `models` | The id is served verbatim by the provider's listing — the allowlist matches on exact string |
| `plain` | Basic round trip, deliberately without a system prompt so it isolates reachability |
| `system_prompt` | The system channel arrives and is obeyed; instructions contradict the obvious answer, so a dropped or rejected prompt fails |
| `schema` | JSON under production's `UNIVERSAL_OUTPUT_SCHEMA`, sent at the provider's own strictness (`Adapter#schema_payload`) and repaired the way production repairs it (`Adapter#unwrap_json`). Fails unless an item comes back with `source_url` null — a digest feed depends on that branch |
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
2. Add the row to `LlmModelCapability::ENTRIES`.
3. Add a rates entry in `config/llm_rates.yml`, verified against the provider's
   published pricing — costs shown to users come from it.
4. If the pair becomes a provider's default, `LlmProvider#default_model` moves
   too; an invariant test requires every provider's default to be in the matrix.

Re-run the probe when the production call shape changes, not only when adding a
pair — a change to how requests are built invalidates earlier evidence.

## Adding a provider

Before a pair can be probed, the provider needs:

- an `LlmProvider` entry (RubyLLM provider key, default model, API base if it
  rides another provider's adapter);
- an `LlmClient::Adapter::REGISTRY` entry, which a test requires for every
  registered provider — `Adapter.for` raises `KeyError` without one, after the
  provider has billed the call. Point it at `Base` unless the provider needs
  response repair, one-call extraction, or a strictness other than the default
  (OpenAI's strict mode cannot express the optional keys
  `UNIVERSAL_OUTPUT_SCHEMA` carries, so it sends the schema unconstrained);
- a probe job pinning the pair, subclassing `LlmCapabilityProbeJob` with
  `PROVIDER`/`MODEL` and registered in `JobRun::RUNNABLE_JOBS`;
- an `AiCredential` for it, named after that new job without the `Job` suffix
  (`<TheNewProbeJob>.credential_name`), on the account that will run the probe.

There is nothing to keep in sync: the probe reaches the provider through
`AiCredential#chat`, so it is configured by the same `LlmProvider#configure`
production uses.
