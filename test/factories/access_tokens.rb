FactoryBot.define do
  factory :access_token do
    association :user
    sequence(:name) { |n| "Token #{n}" }
    state { :pending }
    last_used_at { nil }
    host { "https://candy.freefeed.net" }

    token { "freefeed_token_#{SecureRandom.hex(16)}" }
    encrypted_token { token }

    trait :without_token do
      token { nil }
      encrypted_token { nil }
    end

    trait :active do
      state { :active }
      owner { "testuser" }
      sequence(:freefeed_user_id) { |n| "ff-user-#{n}" }
      # Validation records these, so an active token always carries them.
      scopes { AccessToken::TOKEN_SCOPES }
    end

    trait :inactive do
      state { :inactive }
    end
  end
end
