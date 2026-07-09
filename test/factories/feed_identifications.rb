FactoryBot.define do
  factory :feed_identification do
    association :user
    sequence(:input) { |n| "https://example.com/feed-#{n}.xml" }
    status { :processing }
    candidates { [] }

    trait :success do
      status { :success }
      candidates do
        [
          { "profile_key" => "rss", "title" => "Sample Feed" }
        ]
      end
    end

    trait :failed do
      status { :failed }
      error { "Could not detect feed profile" }
    end
  end
end
