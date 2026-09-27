# AI feed evaluation

Run explicitly in development: `AI_EVAL_CREDENTIAL_ID=<id> AI_EVAL_MODEL=<exact-model-id> AI_EVAL_PROMPT='Find one source post' bin/rails runner script/evaluate_ai_feed.rb`.

One invocation makes one pipeline run, using the application's credential context and execution limits. There is no evaluator retry. The disabled evaluation feed and its chat/usage records roll back; publication is never called. JSON reports normalized posts and the number currently importable. Acceptance by this pipeline does not establish source verification.
