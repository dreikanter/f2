FactoryBot.define do
  factory :feed do
    name { "Sample Feed" }
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

    trait :with_description do
      description { "A sample RSS feed for testing" }
    end

    trait :with_import_threshold do
      import_after { 1.week.ago }
    end
  end
end
