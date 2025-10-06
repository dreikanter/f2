FactoryBot.define do
  factory :feed_profile do
    sequence(:name) { |n| "profile-#{n}-#{SecureRandom.uuid[0..7]}" }
    loader { "http" }
    processor { "rss" }
    normalizer { "rss" }

    trait :rss do
      sequence(:name) { |n| "rss-#{n}-#{SecureRandom.uuid[0..7]}" }
      loader { "http" }
      processor { "rss" }
      normalizer { "rss" }
    end
  end
end
