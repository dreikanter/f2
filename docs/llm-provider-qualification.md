# AI model discovery and diagnostics

## Model selection and free metadata

An active credential's provider listing determines which models can be selected.
New IDs require no qualification entry, SDK registry update, or paid probe.
Published metadata from [models.dev](https://models.dev) is advisory and matched
by exact provider and model ID. Moonshot uses the international `moonshotai`
catalog, matching the configured `api.moonshot.ai` endpoint. Synthesized SDK
capabilities are not treated as evidence. Missing capability values stay unknown;
only explicit non-text output modalities exclude a listed model from the picker.

Catalog refresh runs daily, when a stale picker or credential page opens, and
when **Refresh models** is clicked on the credential page. It has its own tracked
operation and never temporarily deactivates a working credential. Failed listing
requests retain the last successful snapshot. Published metadata is cached daily,
with the last cached data retained on failure. Metadata outages do not prevent
new provider IDs appearing. Reload an open feed picker after refresh completes.

Saved models remain selected and are sent unchanged to the provider even when
omitted from a later listing. The application never silently switches an existing
feed to a different model. A provider may still reject a model at runtime; a
listing or metadata entry is not a compatibility guarantee.

Published prices estimate cost when all used token categories have rates. Existing
exact model rates remain a fallback for older snapshots. Unknown prices appear
as unknown, and aggregate spend indicates when some calls have unknown costs.
Historical zero estimates are unchanged because their original pricing evidence
is unavailable.

## Free staging verification

1. Deploy the PR branch before merging: in GitHub Actions, choose **Deploy
   Staging**, select the PR branch under **Use workflow from**, and run it with
   bootstrap disabled. Wait for deployment to finish.
2. Sign in with a developer account and open
   `/development/jobs/AiModelDiscoveryReportJob/job_runs`.
3. Click **Run**, refresh the list, and open the finished run. Click **Copy
   details** beside its JSON report and share that text.
4. Open an active AI credential, click **Refresh models**, and wait for the
   updated list. Confirm newly listed models appear in the feed picker and a
   previously saved selection stays selected.

The report uses the oldest active staging credential per provider, regardless of
owner. Missing credentials yield `SKIP`. It performs only free provider listing
and published metadata requests and leaves credentials, snapshots, and feeds
unchanged. It records the revision, SDK version, model IDs, advisory metadata,
and missing capability count. Provider error text is omitted to avoid leaking
credentials. `PASS` means listing succeeded, not that all models were tested.

## Text output and bounded fallback

`LlmClient#call` accepts `native_schema: false` to request JSON through
instructions while keeping local schema validation mandatory. With `web: false`,
this path sends neither tools nor an API response-format constraint. It uses the
same credential, exact model ID, and provider transport as the usual path.
Invocation lets the provider resolve the model ID instead of requiring it to
exist in the SDK's bundled registry. Listed models are selectable without an application allowlist.

An explicit model-level rejection of the response-format feature retries once
without the API schema. Other bad requests, invalid schema definitions, tool
rejections, authentication failures, rate limits, and outages still fail. Error
recognition is deliberately narrow; unfamiliar errors remain visible rather
than triggering a speculative retry. A schema fallback can retain web tools;
the existing separate gathering and structuring path remains available.

Malformed or locally invalid output gets at most one correction request using
only the returned content, without web tools or an API schema. The correction
must preserve facts and omit refusals and capability notices from feed items.
Every successful result passes the same local schema validation.

One call context shares a four-attempt limit, the SDK's configured request-time
allowance, and one web-tool budget across gathering, structuring, and retries.
Each completion is capped at 8,192 output tokens. SDK automatic completion
retries are disabled. Each attempt has its own usage row, including malformed
responses and completed tool rounds preceding a provider failure.

The HTTP tests exercise these request shapes without paid calls. Retrieval is
still required by the feed flow; optional retrieval is the next integration phase.

## Optional diagnostics

Paid probes are available for a concrete integration question. They are never
required to list, select, preview, or enable a model. Keep experiments bounded
and inspect individual checks rather than treating the run-level result as a
supported/unsupported verdict.

The developer jobs `AnthropicCapabilityProbeJob`, `KimiCapabilityProbeJob`, and
`OpenAiCapabilityProbeJob` use an active credential on the operator's account,
named after the job without the `Job` suffix. The CLI can select a model or checks:

```sh
bundle exec ruby script/llm_capability_probe.rb --user me@example.com --job KimiCapabilityProbeJob --model kimi-k3
bundle exec ruby script/llm_capability_probe.rb --user me@example.com --job AnthropicCapabilityProbeJob --checks models
```

Probes record their own usage and evidence in job events. Their checks cover
listing, text generation, system instructions, schema output, client tools,
and combined tools/schema. These diagnostic shapes are narrower than the complete
feed flow and do not establish native search availability.

Adding a provider still requires an `LlmProvider` configuration and a
`LlmClient::Adapter` transport. Adding a model from an existing provider requires
only a successful catalog refresh.
