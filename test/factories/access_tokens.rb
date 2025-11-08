FactoryBot.define do
  factory :access_token do
    association :user
    sequence(:name) { |n| "Token #{n}" }
    status { :pending }
    last_used_at { nil }
    host { "https://freefeed.net" }

    token_value = "freefeed_token_#{SecureRandom.hex(16)}"

    token { token_value }
    encrypted_token { token_value }

    trait :without_token do
      token { nil }
      encrypted_token { nil }
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
