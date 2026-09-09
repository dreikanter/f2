FactoryBot.define do
  factory :feed_preview do
    association :user
    feed_profile_key { "rss" }
    sequence(:params) { |n| { "url" => "https://example#{n}.com/feed.xml" } }
    status { :pending }
    data { nil }

    trait :completed do
      status { :ready }
      ready_at { 1.minute.ago }
      data do
        {
          posts: [
            {
              content: "Sample post content",
              source_url: "https://example.com/post/1",
              published_at: 1.hour.ago.iso8601,
              attachments: [],
              uid: "sample-uid-1"
            }
          ],
          stats: {
            total_entries: 1,
            preview_entries: 1,
            normalized_posts: 1
          }
        }
      end
    end

    trait :failed do
      status { :failed }
    end

    trait :processing do
      status { :processing }
    end
  end
end
