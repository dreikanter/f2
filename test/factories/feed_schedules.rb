FactoryBot.define do
  factory :feed_schedule do
    association :feed
    next_run_at { 1.hour.from_now }
    last_run_at { nil }
  end
end
