# OpenAI native extraction verification

Temporary manual verification for #1722. Deploy the PR to staging, then:

1. Create or rename an **active OpenAI credential** to `OpenaiNativeVerification`
   on your own account. No feed setup is needed.
2. Open **Development → Jobs → OpenAI Native Verification → Run**. This explicitly
   authorizes a billable request with that credential and `gpt-5-mini`.
3. Open the completed run and use **Copy details** on its final report. Paste
   that JSON into the #1722 conversation, including a failed report.

The fixed prompt is: “Search the web for the latest Ruby release on ruby-lang.org.
Return one short item with its source URL.” The job uses the native loader and
processor with an unsaved feed. It allows one OpenAI Responses
request, no retries or model substitution, up to four hosted tool calls,
16,384 output tokens (or the model's lower limit), and the shared three-minute
deadline. Each new Run authorizes another request; redelivery of the same run
does not. Nothing schedules this job automatically. It refuses non-staging runs.

PASS requires a completed response with at least one completed native search,
output matching both the exact strict request schema and the processor's schema,
persisted SDK usage, and completion before the deadline. An empty item list can
pass. A response without search is insufficient evidence, even if its JSON is
valid. The job saves its chat and native usage under your user and credential
with preview purpose and no feed association. It saves no feeds, entries, or
posts and does not enable extraction.

The report includes the request schema and limits, model, search count,
validation results, chat state, and SDK token usage/cost estimate. It omits keys,
prompts, generated content, and raw provider errors. Detailed exceptions go to
error tracking; the report supplies the error class, HTTP status, and structured
provider error type/code/parameter, without the message. SDK token
costs exclude hosted search charges and are estimates, not the provider's bill.
Copy only the report, not the persisted transcript.

Automated fixture tests verify the job's behavior, not live provider support.
Remove this temporary job and its registration once the evidence is collected.
