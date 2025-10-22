FactoryBot.define do
  factory :feed_metric do
    association :feed
    date { Date.current }
    posts_count { 0 }
    invalid_posts_count { 0 }

    trait :with_posts do
      posts_count { 5 }
    end

    trait :with_invalid_posts do
      invalid_posts_count { 2 }
    end

    trait :yesterday do
      date { 1.day.ago.to_date }
    end

    trait :last_week do
      date { 1.week.ago.to_date }
    end
  end
end
