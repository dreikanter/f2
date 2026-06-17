FactoryBot.define do
  factory :llm_usage do
    association :user
    feed { nil }
    ai_credential { nil }
    profile_key { "llm_website_extractor" }
    stage { :loader }
    provider { "anthropic" }
    model { "claude-sonnet-4-6" }
    purpose { :scheduled_run }
    input_tokens { 1_000 }
    output_tokens { 500 }
    cache_read_tokens { 0 }
    cache_write_tokens { 0 }
    cost_estimate_cents { 1 }
    outcome { :success }
    started_at { 2.seconds.ago }
    finished_at { 1.second.ago }
    duration_ms { 1_000 }
  end
end
