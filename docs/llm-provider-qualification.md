# AI model discovery and diagnostics

## Model selection and free metadata

An active credential's provider listing determines which models can be selected.
New IDs require no qualification entry, SDK registry update, or paid probe.
Published metadata from [models.dev](https://models.dev) is advisory and matched
by exact provider and model ID. Moonshot uses the international `moonshotai`
catalog, matching the configured `api.moonshot.ai` endpoint. Synthesized SDK
capabilities are not treated as evidence. Missing capability values stay unknown.

Task metadata comes from [LiteLLM's free JSON catalog](https://github.com/BerriAI/litellm/blob/main/model_prices_and_context_window.json),
matched by provider and exact model ID. Only its published task mode is used;
no LiteLLM SDK is installed. Known embedding, image, video,
audio-only, realtime, moderation, ranking, search, and legacy completion tasks
are excluded from new feed selections, along with explicit non-text outputs.
Chat, Responses, unknown task modes, and missing metadata remain selectable.
No model-name patterns, family allowlists, or qualification probes are involved.
Existing saved selections remain visible and are never silently replaced.

The two metadata sources refresh independently and retain their last cached
catalog for up to seven days during outages, with a one-hour retry backoff.
Entries removed from a successful catalog become unknown on refresh. After the
cached catalog expires, its metadata also becomes unknown on refresh. Credential
snapshots do not extend this retention period.

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
and missing capability and task counts. Provider error text is omitted to avoid leaking
credentials. `PASS` means listing succeeded, not that all models were tested.

## Text output and bounded fallback

`LlmClient#call` accepts `native_schema: false` to request JSON through
instructions while keeping local schema validation mandatory. With `web: false`,
this path sends neither tools nor an API response-format constraint. It uses the
same credential, exact model ID, and provider transport as the usual path.
Invocation lets the provider resolve the model ID instead of requiring it to
exist in the SDK's bundled registry. Listed models are selectable without an application allowlist.

An explicit model-level rejection of the response-format feature retries once
without the API schema. Explicit unsupported search or client tools can also
retry with those features disabled. Other bad requests, invalid schema or tool
definitions, authentication failures, rate limits, and outages still fail.
Error recognition is deliberately narrow; unfamiliar errors remain visible
rather than triggering a speculative retry. All retries keep the same model.

Malformed or locally invalid output gets at most one correction request using
only the returned content, without web tools or an API schema. The correction
must preserve facts and omit refusals and capability notices from feed items.
Every successful result passes the same local schema validation.

One call context shares a four-attempt limit, the SDK's configured request-time
allowance, and one web-tool budget across gathering, structuring, and retries.
Each completion is capped at 8,192 output tokens. SDK automatic completion
retries are disabled. Each attempt has its own usage row, including malformed
responses and completed tool rounds preceding a provider failure. Local budget
exhaustion before a request is sent creates no usage row.

The HTTP tests exercise these request shapes without paid calls.

## Optional search

Without an active external search override, the feed uses its AI credential for
provider search: OpenAI Responses web search, Moonshot Formula web search,
Anthropic server web search, or OpenRouter provider-managed search. OpenRouter's
auto engine prefers native search and can fall back to Exa billed to the same
OpenRouter account. It does not require a separate search credential.

An explicitly selected active external search credential takes precedence when
the model can call client tools. If search is unavailable, the model can use
supplied public pages and available knowledge. Supplied pages can also be fetched
independently for models without tools, with the same URL safety checks and
shared tool budget. A request requiring unavailable current evidence may return
no items; creative requests can still produce content. Capability notices and
refusals should not become feed posts.

Provider search gathers cited text before a separate JSON extraction call.
External tools can share extraction where the adapter supports it. Source URLs
are retained through extraction and normalization when the provider supplies them.
Search limits vary by transport and fit within the common attempt, time, and tool
budgets. They are not a universal query-count or dollar cap.

## Usage and estimates

Feed previews and scheduled runs record their model attempts, including failures
and corrections. A saved-feed preview associates its usage and activity with that
feed without saving pending edits or publishing posts. Its external search usage
also counts toward the feed's totals. Unsaved previews belong to the user and
credential; older previews cannot be reliably associated retroactively. Reusing
a cached preview makes no new request and creates no new activity.

Feed totals cover the last 30 days. Missing usage, missing rates for used token
categories, and unpriced native search charges produce an unknown estimate.
OpenRouter search uses its reported total only when it covers the complete charge;
missing totals and BYOK charges stay unknown. Other calls use token-rate estimates.
Prices do not model every provider pricing tier or billing adjustment. Estimates
retain fractional cents and are summed before rounding for display. Small charges
can display `$0.00` individually while contributing to the total. Historical
estimates retain their original precision. The provider's bill remains the source
of actual spending.

## Optional diagnostics

Paid probes are available for a concrete integration question. They are never
required to list, select, preview, or enable a model. Keep experiments bounded
and inspect individual checks rather than treating the run-level result as a
supported/unsupported verdict.

The developer jobs `AnthropicCapabilityProbeJob`, `KimiCapabilityProbeJob`, and
`OpenAiCapabilityProbeJob` use a credential on the operator's account,
named after the job without the `Job` suffix. The CLI can select a model or checks:

```sh
bundle exec ruby script/llm_capability_probe.rb --user me@example.com --job KimiCapabilityProbeJob --model kimi-k3
bundle exec ruby script/llm_capability_probe.rb --user me@example.com --job AnthropicCapabilityProbeJob --checks models
```

Probes record outcomes, timings, and response evidence in job events. They call
the SDK directly and do not create feed usage records or report spend. Their
checks cover listing, text generation, system instructions, schema output,
client tools, and combined tools/schema. These diagnostic shapes are narrower
than the complete feed flow and do not exercise its native search transports or
automatic fallbacks. A failed check does not disable a credential or model.
Every completion has an output cap, and both client tools share one round budget.

Adding a provider still requires an `LlmProvider` configuration and a
`LlmClient::Adapter` transport. Adding a model from an existing provider requires
only a successful catalog refresh.
