FactoryBot.define do
  factory :search_credential do
    association :user
    provider { "serper" }
    sequence(:display_name) { |n| "Serper credential #{n}" }
    credential_data { { "api_key" => "serper-#{SecureRandom.hex(16)}" } }
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
      after(:create) do |credential|
        credential.user.update!(default_search_credential: credential)
      end
    end
  end
end
