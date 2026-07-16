require "test_helper"

class FeedRefreshWorkflowCounterTest < ActiveSupport::TestCase
  test "#execute should update the imported posts counter after bulk insert" do
    feed = create(:feed, url: "https://example.com/feed.xml", feed_profile_key: "rss")
    published_at = 1.hour.ago
    rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <item>
            <guid>entry-123</guid>
            <title>Test Entry</title>
            <description>Test description</description>
            <link>https://example.com/entry-123</link>
            <pubDate>#{published_at.rfc822}</pubDate>
          </item>
        </channel>
      </rss>
    RSS
    stub_request(:get, feed.url).to_return(body: rss, status: 200)

    FeedRefreshWorkflow.new(feed).execute

    assert_equal 1, feed.reload.imported_posts_count
  end
end
