FactoryBot.define do
  factory :user do
    sequence(:email_address) { |n| "user#{n}@example.com" }
    sequence(:name) { |n| "User #{n}" }
    password { "password1234567890" }

    trait :admin do
      after(:create) do |user|
        create(:permission, user: user, name: "admin")
      end
    end
  end
end
