# AI feed evaluation

Run explicitly in development: `AI_EVAL_CREDENTIAL_ID=<id> AI_EVAL_MODEL=<exact-model-id> AI_EVAL_CASE=qualifying bin/rails runner script/evaluate_ai_feed.rb > /tmp/ai-feed-live.jsonl`.

Choose one case from `script/ai_feed_cases.yml` (default: `qualifying`). Every invocation runs exactly one case once; there is no batch or repetition option. Failure reports contain error classes and retained usage, excluding provider error messages. Setup errors exit with status 1 and a JSON error class. Counts unavailable after pipeline failure are null.

One invocation makes one pipeline run, using the application's credential context and execution limits. There is no evaluator retry. The disabled evaluation feed and its chat/usage records roll back; publication is never called. JSON reports normalized posts and the number currently importable. Acceptance by this pipeline does not establish source verification.

Reports include the Git revision, requested and usage-recorded model/provider, application time zone, start time, latency, prompt/configuration, raw candidate fields, normalized outcomes, and retained token/cost data (USD). `filtered` counts candidates removed by refresh selection; `rejected` counts normalizer rejections. Model-reported candidate fields are claims, not verified evidence. Source assessment and date requirements belong to the prompt and live evaluation review. Tool charges are unknown; recorded costs must not be presented as complete spend.

`script/ai_feed_cases.yml` pairs live prompts with sanitized offline response fixtures. These are reconstructed examples, not provider transcripts. Offline tests freeze time at 2026-09-27 18:00 UTC and exercise pipeline behavior. Historical X ID, cross-domain alias, and truncated-text scenarios remain in the saved baseline; they do not define application verification rules.

To append the current offline reports to a JSONL artifact, run `AI_EVAL_OFFLINE_REPORT=/tmp/ai-feed-offline.jsonl bin/rails test test/services/ai_feed_evaluation_cases_test.rb`. Each line is labeled `offline_fixture`; its model usage and cost are stubbed, not paid measurements. Normal tests use no live credentials.

## September 27 baseline and handoff

Prerequisite: `6c39a934` (merged main). Evaluated code: `5ecb360855504d1805a09b523d6bfa84bf0e5a2c`. The baseline commit adds only evidence and documentation; the pipeline remains unchanged. Apply the PR stack in order: [#1858](https://github.com/dreikanter/f2/pull/1858), [#1859](https://github.com/dreikanter/f2/pull/1859), [#1860](https://github.com/dreikanter/f2/pull/1860), [#1861](https://github.com/dreikanter/f2/pull/1861), then the baseline PR. Continue from its final revision named in the #1849 completion handoff.

- [Live JSONL](evaluations/ai-feed-baseline-live-2026-09-27.jsonl): one `qualifying` invocation using the command above with `AI_EVAL_MODEL=gpt-5.6-luna` and an active development OpenAI credential. Requested and recorded model IDs match. One candidate became one importable post in 24.855 seconds, with six recorded search calls and $0.00821305 in recorded cost. Tool charges remain unknown. No post was published.
- [Offline JSONL](evaluations/ai-feed-baseline-offline-2026-09-27.jsonl): eight reconstructed fixture runs through the shared pipeline using the command above. Model identity `gpt-5-nano`, tokens, and costs are stubbed test data. These records are not live model qualifications.

The live candidate's timezone-free claimed publication time became 11:00 UTC. Its X ID encodes 08:00:28.603 UTC (`((2104118965211467894 >> 22) + 1288834974657) / 1000` seconds since Unix epoch). Acceptance therefore does not establish timestamp accuracy. Existence and quoted text were not independently checked. One accepted live result does not establish repeatability or source quality.

Validation at the evaluated revision: 13 evaluator tests / 152 assertions pass; all 18 JavaScript tests and RuboCop pass. The full local Rails suite runs 4,297 tests with one pre-existing macOS encoded-loopback failure in `PublicUrlTest`, reproduced in the original checkout. Linux CI passes this test. There are no migrations or user-facing runtime changes.

Keep the evaluator aligned with final selection limits, preview parity, and cost accounting. Preserve the fixture/live distinction, isolated history, bounded invocation, and absent publication path. Current refresh selection is reused through its private stage methods; update that call when selection gains a shared public interface. Exceptions retain only available usage, so interrupted in-flight spend may be missing. No legacy execution mode is retained.

## Dates and source references

Single-source items use `source_url`; synthesized posts preserve any citations in their body and use `source_url: null`. F2 does not independently verify those citations. A blank or unreadable source date stays null on `FeedEntry`, so it passes an explicit import threshold as other undated feeds do. Generated items use the run start for ordering and thresholds. `Post.published_at` uses the existing display/order fallback for undated entries; it is not evidence of a source publication date. Raw model fields remain available on the entry.

The model receives the run time in UTC and the application's time zone as the default for relative dates. An explicit timezone in the user's prompt takes precedence.

Single-source identities use the shared URL normalizer. Synthesized/generated items use the job's logical run ID plus their response position, ignoring model-provided IDs and arbitrary citations. Retrying a refresh job preserves those identities; a separately scheduled run gets new identities. Direct loader/evaluator runs default to their chat ID. Similar wording across separate runs is not semantically deduplicated.
