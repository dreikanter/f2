FactoryBot.define do
  factory :permission do
    user
    name { Permission::ADMIN }
  end
end
