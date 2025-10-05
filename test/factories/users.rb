FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "user#{n}@example.com" }
    password { "password123" }

    trait :admin do
      after(:create) do |user|
        create(:permission, user: user, name: "admin")
      end
    end
  end
end
