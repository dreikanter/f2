FactoryBot.define do
  factory :feed_profile do
    association :user
    sequence(:name) { |n| "profile-#{n}-#{SecureRandom.uuid[0..7]}" }
    loader { "http_loader" }
    processor { "rss_processor" }
    normalizer { "rss_normalizer" }

    trait :rss do
      sequence(:name) { |n| "rss-#{n}-#{SecureRandom.uuid[0..7]}" }
      loader { "http_loader" }
      processor { "rss_processor" }
      normalizer { "rss_normalizer" }
    end
  end
end