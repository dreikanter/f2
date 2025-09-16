FactoryBot.define do
  factory :post do
    feed { association(:feed) }
    feed_entry { association(:feed_entry, feed: feed) }
    uid { "post-#{SecureRandom.uuid}" }
    status { :draft }
    published_at { 2.hours.ago }
    link { "https://example.com/post" }
    text { "Sample post content" }
    attachment_urls { [] }
    comments { [] }
    validation_errors { [] }

    trait :enqueued do
      status { :enqueued }
    end

    trait :rejected do
      status { :rejected }
      validation_errors { ["blank_text"] }
    end

    trait :published do
      status { :published }
      freefeed_post_id { "freefeed-#{SecureRandom.uuid}" }
    end

    trait :failed do
      status { :failed }
    end

    trait :with_attachments do
      attachment_urls { ["https://example.com/image1.jpg", "https://example.com/image2.png"] }
    end

    trait :with_comments do
      comments { ["Additional context about this post"] }
    end

    trait :without_feed_entry do
      feed_entry { nil }
    end
  end
end
