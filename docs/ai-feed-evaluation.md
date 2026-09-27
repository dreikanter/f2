# AI feed evaluation

Run explicitly in development: `AI_EVAL_CREDENTIAL_ID=<id> AI_EVAL_MODEL=<exact-model-id> AI_EVAL_PROMPT='Find one source post' bin/rails runner script/evaluate_ai_feed.rb`.

One invocation makes one pipeline run, using the application's credential context and execution limits. There is no evaluator retry. The disabled evaluation feed and its chat/usage records roll back; publication is never called. JSON reports normalized posts and the number currently importable. Acceptance by this pipeline does not establish source verification.

Reports include the Git revision, requested and usage-recorded model/provider, application time zone, start time, latency, prompt/configuration, raw candidate fields, normalized outcomes, and retained token/cost data (USD). `filtered` counts candidates removed by refresh selection; `rejected` counts normalizer rejections. Model-reported candidate fields are claims, not verified evidence. Structured windows and source-verification results are unavailable in the current contract. Tool charges are unknown; recorded costs must not be presented as complete spend.
