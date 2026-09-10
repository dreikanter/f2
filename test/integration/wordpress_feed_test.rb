require "test_helper"

class WordpressFeedTest < ActiveSupport::TestCase
  URL = "https://example.com/feed"

  test "identification should prefer WordPress when the feed declares its generator" do
    result = FeedProfileDetector.call(input: URL, fetched_body: source)

    assert_equal %w[wordpress rss], result.candidates.map(&:profile_key)
    assert_not ProfileMatcher::WordpressProfileMatcher.new(URL, "<html>WordPress</html>").match?
  end

  test "preview should preserve body panels and a full caption without the sharing thumbnail" do
    preview = create(:feed_preview, feed_profile_key: "wordpress", params: { "url" => URL })
    stub_request(:get, URL).to_return(body: source)

    FeedPreviewWorkflow.new(preview, run_id: preview.run_id).execute

    assert preview.reload.ready?
    post = preview.posts_data.sole
    assert_equal "Sample comic - https://example.com/comic", post.fetch("content")
    assert_equal ["https://example.com/first.png", "https://example.com/second.png"], post.fetch("attachments")
    assert_equal ["Full caption with a link (https://example.org/extra)."], post.fetch("comments")
  end

  test "import should retain the source identity and apply the publication cutoff" do
    feed = create(:feed, feed_profile_key: "wordpress", url: URL, import_after: Time.utc(2026, 9, 8))
    stub_request(:get, URL).to_return(body: source)

    FeedRefreshWorkflow.new(feed).execute

    assert_equal ["https://example.com/?p=123"], feed.feed_entries.pluck(:uid)
    assert_equal [Time.utc(2026, 9, 9, 10)], feed.posts.pluck(:published_at)
  end

  private

  def source
    file_fixture("feeds/wordpress/feed.xml").read
  end
end
