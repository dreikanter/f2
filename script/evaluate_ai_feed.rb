require_relative "ai_feed_evaluation"

begin
  name = ENV.fetch("AI_EVAL_CASE", "qualifying")
  scenario = YAML.safe_load_file(Rails.root.join("script/ai_feed_cases.yml")).fetch(name)
  report = AiFeedEvaluation.run(
    credential: AiCredential.find(ENV.fetch("AI_EVAL_CREDENTIAL_ID")),
    model: ENV.fetch("AI_EVAL_MODEL"),
    **scenario.slice("prompt", "max_items", "imported_urls", "web_search").symbolize_keys
  )
  puts JSON.generate(report.merge(mode: "live", case: name, case_count: 1, repetitions: 1))
rescue StandardError => error
  Rails.error.report(error, context: { evaluation: true })
  warn JSON.generate(error: error.class.name)
  exit 1
end
