# AI provider integration

The application uses RubyLLM `2.0.0.rc3` and currently registers OpenAI only.
Scheduled AI feed refreshes and previews use the saved model and native OpenAI
search. Both link persisted chats and SDK usage to their events. External search
is deferred; the AI loader rejects feeds with a search credential before making
requests.

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

The daily schedule and the developer-only model catalog page enqueue
[`RefreshLlmModelsJob`](../app/jobs/refresh_llm_models_job.rb), which calls
`RubyLLM.models.refresh`. Solid Queue prevents concurrent refreshes and reports
active work. A single `LlmModelRefresh` row stores the last successful refresh
time and current failure independently of disposable queue history. Reload
an open feed form to see updated choices. A failed refresh retains the current
registry. Refresh never reads user keys or changes credential usability; it makes
no inference request.

## Free authentication validation

[`AiCredential`](../app/models/ai_credential.rb) delegates local field checks and
remote authentication to its registered `AiCredentialValidator` implementation.
[`AiCredentialValidation`](../app/services/ai_credential_validation.rb) owns the
validation run and stale-response guards. Provider adapters configure inference
requests separately from credential validation.

For OpenAI, [`AiCredentialValidator::Openai`](../app/services/ai_credential_validator/openai.rb)
checks the key with an authenticated `GET /v1/models`. Successful response bodies
are discarded, including empty or non-JSON bodies. Failed responses are inspected
only for sanitized error classification.

Saving a new or changed key starts asynchronous validation. `AiCredential`
stores the encrypted key and usability; `OperationRun` records validation
progress and its 15-minute deadline. Validation and catalog refresh are independent.
Rechecking an unchanged key preserves its usability. Changing key data makes
it inactive until validation succeeds. Stale responses cannot replace newer results.

OpenAI's HTTP 401 with `invalid_api_key` deactivates a key and disables its dependent
feeds. Permission restrictions, quota/rate limits, connection failures, and
timeouts preserve an already usable key. They leave new or changed keys inactive.

## Extraction and preview lifecycle

[`LlmProvider::Base`](../app/models/llm_provider/base.rb) defines the adapter
interface for isolated SDK contexts, API protocols, and provider-specific request
options. [`LlmExecution`](../app/services/llm_execution.rb) applies shared request,
output, and tool budgets while preserving the selected provider and model.

[`LlmLoader`](../app/services/loader/llm_loader.rb) prepares a fresh persisted chat,
system instructions, user request, and output schema. It checks response completion
and returns an `LlmResult`. The shared prompt defines content and provenance rules;
provider adapters supply API configuration.

[`LlmProcessor`](../app/services/processor/llm_processor.rb) validates response JSON
and builds feed entries before completing the extraction through `LlmResult`.
[`LlmChat`](../app/models/llm_chat.rb) owns the shared deadline and guarded terminal
transitions. Late output cannot complete successfully; late SDK usage is retained.
The normalizer then applies the ordinary publication rules.

[`FeedPreviewWorkflow`](../app/services/feed_preview_workflow.rb) uses the same
pipeline with preview attribution and the earlier preview deadline. Its activity
event links to the chat, including for unsaved feeds. Preview state has its own
stale-run guards: a valid extraction may succeed even when its preview can no longer
publish the result.

## Usage reporting and retention

[`LlmUsageReport`](../app/services/llm_usage_report.rb) reports retained
`RubyLLM::ActiveRecord::Usage` records attributed through chats. RubyLLM owns request
recording, token counts, and cost estimates; f2 owns attribution, reporting, and
retention. The historical `llm_usages` table and its event references were removed.

Usage appears in event details, feed and credential statistics, and read-only admin
chat history. Feed statistics cover the last 30 days. Missing costs remain unknown,
and interrupted requests may leave no usage record. Catalog refresh and validation
produce no inference usage. Chats, messages, and SDK usages are retained for two
months; retention also removes their event references.

## Provider verification

HTTP fixture tests cover authentication, catalog persistence, exact model selection,
refresh and preview attribution, output validation, deadlines, and SDK reporting.
To check selectors with an authorized credential, validate the key and reopen a feed
form after catalog refresh. Confirm the saved model is preserved and another
credential for the same provider shows the same choices. These free requests do not
establish extraction compatibility.

The authorized staging verification in [#1759](https://github.com/dreikanter/f2/pull/1759)
passed for `gpt-5-mini`: native search, strict output, processor validation, SDK usage,
and deadline completion. That temporary verification job was not merged.

For each additional provider, register its adapter and credential validator, then
verify its search and structured-output behavior with the shared content contract.
Add provider-specific execution stages only when its integration requires them.
Live inference checks require explicit authorization because they may incur charges.
The completed integration plan is recorded in [#1722](https://github.com/dreikanter/f2/issues/1722).
