FactoryBot.define do
  factory :feed do
    association :user
    sequence(:name) { |n| "sample-feed-#{n}" }
    url { "https://example.com/feed.xml" }
    cron_expression { "0 */6 * * *" }
    loader { "http" }
    processor { "rss" }
    normalizer { "rss" }
    state { :enabled }
    description { "" }
    import_after { nil }

    trait :with_schedule do
      after(:create) do |feed|
        create(:feed_schedule, feed: feed)
      end
    end

    trait :paused do
      state { :paused }
    end

    trait :disabled do
      state { :disabled }
    end
  end
end
