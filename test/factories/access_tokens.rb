FactoryBot.define do
  factory :access_token do
    association :user
    sequence(:name) { |n| "Token #{n}" }
    status { :pending }
    last_used_at { nil }

    transient do
      with_token { true }
    end

    after(:build) do |access_token, evaluator|
      if evaluator.with_token
        # Simulate user-provided Freefeed token
        token_value = "freefeed_token_#{SecureRandom.hex(16)}"
        access_token.token = token_value
        access_token.encrypted_token = token_value
      end
    end

    trait :active do
      status { :active }
      owner { "testuser" }
    end

    trait :inactive do
      status { :inactive }
    end

    trait :recently_used do
      last_used_at { 1.hour.ago }
    end
  end
end
