FactoryBot.define do
  factory :feed_identification do
    association :user
    sequence(:url) { |n| "https://example.com/feed-#{n}.xml" }
    status { :processing }
    candidates { [] }

    trait :success do
      status { :success }
      candidates do
        [
          {
            "profile_key" => "rss",
            "rank" => 0,
            "depends_on_ai" => false,
            "title" => "Sample Feed",
            "rank_reason" => "specific_match"
          }
        ]
      end
    end

    trait :failed do
      status { :failed }
      error { "Could not detect feed profile" }
    end
  end
end
