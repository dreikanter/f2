FactoryBot.define do
  factory :llm_credential do
    association :user
    provider { "anthropic" }
    sequence(:display_name) { |n| "Claude credential #{n}" }
    credential_data { { "api_key" => "sk-ant-#{SecureRandom.hex(16)}" } }
    is_default { false }
    state { :pending }

    trait :active do
      state { :active }
      last_validated_at { 1.hour.ago }
    end

    trait :inactive do
      state { :inactive }
      last_error { "Invalid API key" }
    end

    trait :default do
      is_default { true }
    end
  end
end
