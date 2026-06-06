FactoryBot.define do
  factory :event_reference do
    event
    reference { association(:post) }
  end
end
