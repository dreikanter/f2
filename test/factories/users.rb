FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "user#{n}@example.com" }
    sequence(:name) { |n| "User #{n}" }
    password { "password123" }
    state { :active }

    trait :admin do
      after(:create) do |user|
        create(:permission, user: user, name: "admin")
      end
    end

    trait :suspended do
      state { :suspended }
      suspended_at { Time.current }
    end

    trait :inactive do
      state { :inactive }
    end
  end
end
