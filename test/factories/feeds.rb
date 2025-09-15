FactoryBot.define do
  factory :feed do
    association :user
    sequence(:name) { |n| "sample-feed-#{n}" }
    url { "https://example.com/feed.xml" }
    cron_expression { "0 */6 * * *" }
    loader { "http" }
    processor { "rss" }
    normalizer { "rss" }
    state { :disabled }
    description { "" }
    import_after { nil }
    target_group { "testgroup" }

    after(:build) do |feed|
      if feed.user && feed.access_token.nil?
        feed.access_token = create(:access_token, :active, user: feed.user)
      end
    end

    trait :with_schedule do
      after(:create) do |feed|
        create(:feed_schedule, feed: feed)
      end
    end

    trait :disabled do
      state { :disabled }
    end

    trait :without_access_token do
      access_token { nil }
      target_group { nil }
      after(:build) { |feed| feed.access_token = nil }
    end
  end
end
