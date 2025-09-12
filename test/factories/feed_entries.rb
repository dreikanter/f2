FactoryBot.define do
  factory :feed_entry do
    feed { association(:feed) }
    external_id { "entry-#{rand(1000)}" }
    title { "Sample Feed Entry" }
    content { "This is sample content for a feed entry." }
    published_at { 2.hours.ago }
    source_url { "https://example.com/entry" }
    status { :pending }
    raw_data { { id: external_id, title: title, content: content } }
  end
end
