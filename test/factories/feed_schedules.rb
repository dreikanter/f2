FactoryBot.define do
  factory :feed_schedule do
    association :feed
    next_run_at { 1.hour.from_now }
    last_run_at { nil }

    trait :past_due do
      next_run_at { 1.hour.ago }
    end

    trait :future do
      next_run_at { 1.hour.from_now }
    end

    trait :with_last_run do
      last_run_at { 2.hours.ago }
    end
  end
end
