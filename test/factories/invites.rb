FactoryBot.define do
  factory :invite do
    association :created_by_user, factory: :user
    invited_user { nil }
  end
end
