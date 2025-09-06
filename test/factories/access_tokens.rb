FactoryBot.define do
  factory :access_token do
    association :user
    sequence(:name) { |n| "Token #{n}" }
    is_active { true }
    last_used_at { nil }

    transient do
      with_token { true }
    end

    after(:build) do |access_token, evaluator|
      if evaluator.with_token
        access_token.generate_token
      elsif access_token.token_digest.blank?
        access_token.token_digest = BCrypt::Password.create("dummy_token_#{SecureRandom.hex(8)}")
      end
    end

    trait :inactive do
      is_active { false }
    end

    trait :recently_used do
      last_used_at { 1.hour.ago }
    end
  end
end
