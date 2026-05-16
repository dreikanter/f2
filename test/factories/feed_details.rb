FactoryBot.define do
  factory :feed_detail do
    association :user
    sequence(:url) { |n| "https://example.com/feed-#{n}.xml" }
    status { :processing }
    candidates { [] }

    trait :success do
      status { :success }
      feed_profile_key { "rss" }
      title { "Sample Feed" }
      candidates do
        [
          { "profile_key" => "rss", "rank" => 0, "depends_on_ai" => false, "title" => "Sample Feed" }
        ]
      end
    end

    trait :failed do
      status { :failed }
      error { "Could not detect feed profile" }
    end
  end
end
