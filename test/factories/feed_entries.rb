FactoryBot.define do
  factory :feed_entry do
    feed { association(:feed) }
    uid { "entry-#{SecureRandom.uuid}" }
    published_at { 2.hours.ago }
    status { :pending }
    raw_data { { id: uid, title: "Sample Feed Entry", url: "https://example.com/entry" } }
  end
end
