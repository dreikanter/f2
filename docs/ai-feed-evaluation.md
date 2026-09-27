# AI feed evaluation

Run explicitly in development: `AI_EVAL_CREDENTIAL_ID=<id> AI_EVAL_MODEL=<exact-model-id> AI_EVAL_PROMPT='Find one source post' bin/rails runner script/evaluate_ai_feed.rb`.

One invocation makes one pipeline run, using the application's credential context and execution limits. There is no evaluator retry. The disabled evaluation feed and its chat/usage records roll back; publication is never called. JSON reports normalized posts and the number currently importable. Acceptance by this pipeline does not establish source verification.

Reports include the Git revision, requested and usage-recorded model/provider, application time zone, start time, latency, prompt/configuration, raw candidate fields, normalized outcomes, and retained token/cost data (USD). `filtered` counts candidates removed by refresh selection; `rejected` counts normalizer rejections. Model-reported candidate fields are claims, not verified evidence. Structured windows and source-verification results are unavailable in the current contract. Tool charges are unknown; recorded costs must not be presented as complete spend.

`script/ai_feed_cases.yml` pairs live prompts with sanitized offline response fixtures. These are reconstructed examples, not provider transcripts. The qualifying permalink, short quote, and truncated preview reuse the September 27 research example; other text is synthetic. Offline tests freeze time at 2026-09-27 18:00 UTC and assert current behavior, including incorrect acceptance. The stale ID dates to 2024 despite its recent claimed date; absent dates become the run time; equivalent X/Twitter URLs remain distinct; truncated evidence is not checked. Update these expectations as the replacement contract ships.

To append all eight offline reports to a JSONL artifact, run `AI_EVAL_OFFLINE_REPORT=/tmp/ai-feed-offline.jsonl bin/rails test test/services/ai_feed_evaluation_cases_test.rb`. Each line is labeled `offline_fixture`; its model usage and cost are stubbed, not paid measurements. Normal tests use no live credentials.
