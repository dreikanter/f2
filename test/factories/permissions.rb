FactoryBot.define do
  factory :permission do
    user
    name { "admin" }
  end
end
