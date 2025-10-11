FactoryBot.define do
  factory :feed_preview do
    association :user
    feed_profile_key { "rss" }
    sequence(:url) { |n| "https://example#{n}.com/feed.xml" }
    status { :pending }
    data { nil }

    trait :completed do
      status { :ready }
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

    trait :with_feed do
      association :feed
    end

    trait :with_multiple_posts do
      status { :ready }
      data do
        {
          posts: 3.times.map do |i|
            {
              content: "Sample post content #{i + 1}",
              source_url: "https://example.com/post/#{i + 1}",
              published_at: (i + 1).hours.ago.iso8601,
              attachments: [],
              uid: "sample-uid-#{i + 1}"
            }
          end,
          stats: {
            total_entries: 3,
            preview_entries: 3,
            normalized_posts: 3
          }
        }
      end
    end
  end
end
