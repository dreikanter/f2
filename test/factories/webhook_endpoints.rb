FactoryBot.define do
  factory :webhook_endpoint do
    association :feed
  end
end
