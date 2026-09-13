# AI model discovery

The application uses RubyLLM `2.0.0.rc2` and currently registers OpenAI only.
Credential validation and automatic/manual model catalog refresh are available.
AI feed extraction remains temporarily unavailable; ordinary feeds continue to
work. Existing feed settings, credential forms, and stored usage displays remain.

## Model listing and selection

[`LlmProvider::Openai`](../app/models/llm_provider/openai.rb) lists models through
the authenticated `GET /v1/models` endpoint using the credential's key.
Discovery is free and makes no inference requests. Provider clients hold a copy
of credential data and build isolated SDK contexts with retries disabled.

[`AiModelCatalog`](../app/services/ai_model_catalog.rb) enriches those IDs with
advisory metadata from RubyLLM's local registry, matched by provider and exact
model ID. This requires no separate metadata request or qualification probe.
IDs missing from the SDK registry remain available.

New selections exclude models whose metadata explicitly lists only non-text
outputs. Missing metadata does not exclude a model, and the catalog is not proof
that a model supports extraction, tools, or strict output. A saved model remains
visible in the feed form even if a later listing omits it.

## Credential validation

Saving new or changed credential data starts asynchronous validation through
the same free listing endpoint. A successful response activates the credential
and saves its catalog, including when the returned list is empty.

The credential's `active` flag records usability;
[`OperationRun`](../app/models/operation_run.rb) records progress and outcome.
Rechecking unchanged credentials keeps them usable. Changing credential data
makes it inactive until validation succeeds; renaming a credential or leaving
saved secret fields blank preserves its data and usability.

Validation takes precedence over catalog refresh: starting validation supersedes
existing refresh work, and new refreshes wait until validation completes or
reaches its deadline. Responses from superseded operations or replaced
credential data cannot overwrite the current result.

Validation and refresh deactivate a key only when OpenAI returns HTTP 401 with
the explicit `invalid_api_key` code. This records a deactivation event and disables
its enabled dependent feeds. Permission restrictions, quota/rate limits,
connection failures, malformed responses, and timeouts preserve prior usability
and the saved catalog. New or changed credentials stay inactive after these
failures.

## Catalog refresh

The hourly `RefreshAiModelCatalogsJob` checks active credentials and refreshes
catalogs at least one day old. Automatic attempts are spaced at least one hour
apart during failures. **Refresh models** bypasses freshness and retry delays,
while still respecting validation and existing refresh work.

Validation and refresh have recorded 15-minute operation deadlines. Polling reads
their progress without changing state. A failed refresh retains the saved
snapshot; a later successful catalog update clears the old failure indication.
Reload an open feed form to see a refreshed catalog.

## Checking discovery

On development or staging, using an OpenAI credential you own:

1. Create or recheck the credential and wait for validation to finish.
2. Confirm that successful validation leaves it active and displays the returned
   model catalog. An empty catalog can still be a successful credential check.
3. Click **Refresh models**, wait for completion, and check the updated timestamp.
4. Reopen an existing feed's settings and confirm its saved model remains selected.

These checks update the credential and catalog through free listing requests.
They do not test extraction or establish compatibility for every listed model.

## Accounting and remaining work

Stored usage remains visible in event details and feed statistics. Feed totals
cover the last 30 days; missing costs remain unknown rather than being counted
as zero. Discovery creates no inference usage.

[The replacement plan](https://github.com/dreikanter/f2/issues/1722) tracks
transcript storage, durable request accounting, extraction, bounded retrieval,
workflow reconnection, and admin history. The SDK fixture checks establish
behavior at the SDK/HTTP boundary. Before implementing native extraction, the
plan still requires evidence that the exact selected model accepts native
search and the strict feed schema together. Follow its bounded, explicitly
authorized provider check.
