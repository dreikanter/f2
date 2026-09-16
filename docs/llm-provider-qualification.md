# AI models and credential validation

The application uses RubyLLM `2.0.0.rc2` and currently registers OpenAI only.
Scheduled refreshes of existing enabled AI feeds use native OpenAI search and
the saved model. Each refresh links its persisted chat and SDK usage to its event;
only validated output completed before the chat deadline enters publication.
External-search feeds remain paused. Enabling AI feeds, manual refresh, and
preview remain unavailable pending their integration. Existing feed settings,
credential forms, and historical usage displays remain available.

## Shared model catalog

RubyLLM owns fetching, merging, and persistence in `ruby_llm_models`.
[`LlmModels`](../app/models/llm_models.rb) reads those records directly so web
and worker processes see the latest persisted catalog. Before the first refresh,
selectors read a separate local registry instance without changing the process-wide
SDK registry or making a network request.

All credentials for a provider share the same public models. Feed choices exclude
known non-text outputs; missing metadata remains selectable. Capabilities are
advisory and do not establish account access or extraction compatibility.
Saved model IDs remain visible and are never silently replaced.

**Refresh models** and the daily schedule enqueue
[`RefreshLlmModelsJob`](../app/jobs/refresh_llm_models_job.rb), which calls
`RubyLLM.models.refresh`. Solid Queue prevents concurrent refreshes and reports
active work. A single `LlmModelRefresh` row stores the last successful refresh
time and current failure independently of disposable queue history. Pruning jobs
therefore preserves the update time and cannot revive an older failure. Reload
an open feed form to see updated choices.
A failed refresh retains the current registry. Refresh never reads user keys or
changes credential usability; it makes no inference request.

## Free authentication validation

[`LlmProvider::Openai`](../app/models/llm_provider/openai.rb) checks the key with
an authenticated `GET /v1/models`. Successful response bodies are discarded,
including empty or non-JSON bodies. Failed responses are inspected only for
sanitized error classification. Provider clients also build isolated SDK contexts.

Saving a new or changed key starts asynchronous validation. `AiCredential`
stores the encrypted key and usability; `OperationRun` records validation
progress and its 15-minute deadline. Validation and catalog refresh are independent.
Rechecking an unchanged key preserves its usability. Changing key data makes
it inactive until validation succeeds. Stale responses cannot replace newer results.

Only HTTP 401 with `invalid_api_key` deactivates a key and disables its dependent
feeds. Permission restrictions, quota/rate limits, connection failures, and
timeouts preserve an already usable key. They leave new or changed keys inactive.

## Verification and remaining work

HTTP fixture tests exercise authentication, SDK registry persistence, shared
refreshes, failures, exact model selection, and stale process caches. To check the
UI with an authorized credential, validate the key, refresh models, and reopen a
feed form. Confirm that the selected model is preserved and a second credential
for the same provider shows the same choices. These free requests do not establish
extraction compatibility.

Stored usage remains visible in event details and feed statistics. Feed totals
cover the last 30 days; missing costs remain unknown. Catalog refresh and
validation produce no inference usage.

[The replacement plan](https://github.com/dreikanter/f2/issues/1722) tracks the
remaining extraction and accounting work. The authorized staging verification in
[#1759](https://github.com/dreikanter/f2/pull/1759) passed for `gpt-5-mini`: native
search, strict output, processor validation, SDK usage, and deadline completion.
That temporary verification job was not merged. Reporting still uses historical
usage records until the separate SDK reporting integration.
