require "test_helper"

class LunarbaboonFeedTest < ActiveSupport::TestCase
  URL = "http://www.lunarbaboon.com/comics/rss.xml"

  test "identification should prefer the comic profile" do
    result = FeedProfileDetector.call(input: URL, fetched_body: source)

    assert_equal %w[lunarbaboon rss], result.candidates.map(&:profile_key)
  end

  test "preview should encode image filename spaces and retain bonus links" do
    preview = create(:feed_preview, feed_profile_key: "lunarbaboon", params: { "url" => URL })
    stub_request(:get, URL).to_return(body: source)

    FeedPreviewWorkflow.new(preview, run_id: preview.run_id).execute

    assert preview.reload.ready?
    post = preview.posts_data.sole
    assert_equal ["https://images.example.com/first%20panel.jpg?version=1", "https://images.example.com/second%20panel.jpg"], post.fetch("attachments")
    assert_includes post.fetch("content"), "Full comic and bonus (https://example.org/bonus)"
  end

  test "import should preserve comic identity and publication date" do
    feed = create(:feed, feed_profile_key: "lunarbaboon", url: URL, import_after: Time.utc(2026, 9, 8))
    stub_request(:get, URL).to_return(body: source)

    FeedRefreshWorkflow.new(feed).execute

    assert_equal ["sample:strip"], feed.feed_entries.pluck(:uid)
    assert_equal [Time.utc(2026, 9, 9, 10)], feed.posts.pluck(:published_at)
  end

  private

  def source
    file_fixture("feeds/lunarbaboon/feed.xml").read
  end
end
