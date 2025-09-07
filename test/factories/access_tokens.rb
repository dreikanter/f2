FactoryBot.define do
  factory :access_token do
    association :user
    sequence(:name) { |n| "Token #{n}" }
    status { :active }
    last_used_at { nil }

    transient do
      with_token { true }
    end

    after(:build) do |access_token, evaluator|
      if evaluator.with_token
        # Simulate user-provided Freefeed token
        token_value = "freefeed_token_#{SecureRandom.hex(16)}"
        access_token.token = token_value
        access_token.token_digest = BCrypt::Password.create(token_value)
      elsif access_token.token_digest.blank?
        access_token.token_digest = BCrypt::Password.create("dummy_token_#{SecureRandom.hex(8)}")
      end
    end

    trait :inactive do
      status { :inactive }
    end

    trait :recently_used do
      last_used_at { 1.hour.ago }
    end
  end
end
