FactoryBot.define do
  factory :invite do
    association :created_by_user, factory: :user
    association :invited_user, factory: :user, optional: true
  end
end
