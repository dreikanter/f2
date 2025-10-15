FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "user#{n}@example.com" }
    sequence(:name) { |n| "User #{n}" }
    password { "password123" }

    after(:create) do |user|
      user.onboarding&.destroy
    end

    trait :admin do
      after(:create) do |user|
        create(:permission, user: user, name: "admin")
      end
    end

    trait :with_onboarding do
      after(:create) do |user|
        user.create_onboarding! unless user.onboarding
      end
    end
  end
end
