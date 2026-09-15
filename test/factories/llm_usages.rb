FactoryBot.define do
  factory :llm_usage do
    association :user
    feed { nil }
    ai_credential { nil }
    profile_key { "llm" }
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

    trait :pending do
      outcome { :pending }
      deadline_at { 5.minutes.from_now }
      finished_at { nil }
      duration_ms { nil }
      input_tokens { nil }
      output_tokens { nil }
      cache_read_tokens { nil }
      cache_write_tokens { nil }
      cost_estimate_cents { nil }
    end
  end
end
