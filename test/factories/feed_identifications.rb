FactoryBot.define do
  factory :feed_identification do
    association :user
    sequence(:input) { |n| "https://example.com/feed-#{n}.xml" }
    status { :processing }
    candidates { [] }

    trait :working do
      status { :working }
      candidates do
        [
          { "profile_key" => "rss", "title" => "Sample Feed" }
        ]
      end
    end

    trait :no_feed do
      status { :no_feed }
    end
  end
end
