require_relative "ai_feed_evaluation"

report = AiFeedEvaluation.run(
  credential: AiCredential.find(ENV.fetch("AI_EVAL_CREDENTIAL_ID")),
  model: ENV.fetch("AI_EVAL_MODEL"),
  prompt: ENV.fetch("AI_EVAL_PROMPT")
)
puts JSON.pretty_generate(report)
