FactoryBot.define do
  factory :event do
    type { "TestEvent" }
    level { :info }
    message { "Test event message" }
    metadata { {} }
  end
end
