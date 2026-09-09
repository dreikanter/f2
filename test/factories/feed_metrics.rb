FactoryBot.define do
  factory :feed_metric do
    association :feed
    date { Date.current }
    posts_count { 0 }
    invalid_posts_count { 0 }
    published_posts_count { 0 }

    trait :with_published_posts do
      published_posts_count { 4 }
    end
  end
end
