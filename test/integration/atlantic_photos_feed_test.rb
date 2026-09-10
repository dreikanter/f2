require "test_helper"

class AtlanticPhotosFeedTest < ActiveSupport::TestCase
  URL = "https://www.theatlantic.com/feed/channel/photo/"

  test "identification should select the photo profile for its specific feed" do
    result = FeedProfileDetector.call(input: URL, fetched_body: source)

    assert_equal %w[atlantic_photos rss], result.candidates.map(&:profile_key)
    assert_not ProfileMatcher::AtlanticPhotosProfileMatcher.new("https://www.theatlantic.com/feed/all/", source).match?
  end

  test "preview should retain the introduction and independently captioned images" do
    preview = create(:feed_preview, feed_profile_key: "atlantic_photos", params: { "url" => URL })
    stub_request(:get, URL).to_return(body: source)

    FeedPreviewWorkflow.new(preview, run_id: preview.run_id).execute

    assert preview.reload.ready?
    post = preview.posts_data.sole
    assert_equal "Sample gallery (Sample Author) - https://example.com/gallery", post.fetch("content")
    assert_equal ["https://example.com/one.jpg", "https://example.com/two.jpg"], post.fetch("attachments")
    assert_equal "A short introduction.", post.fetch("comments").first
    assert_includes post.fetch("comments").second, "First Photographer"
    assert_includes post.fetch("comments").third, "Second caption with a reference (https://example.org/reference)."
    assert_includes post.fetch("comments").third, "A river"
  end

  test "import should preserve the gallery identity and source date" do
    feed = create(:feed, feed_profile_key: "atlantic_photos", url: URL, import_after: Time.utc(2026, 9, 8))
    stub_request(:get, URL).to_return(body: source)

    FeedRefreshWorkflow.new(feed).execute

    assert_equal ["urn:sample:gallery"], feed.feed_entries.pluck(:uid)
    assert_equal [Time.utc(2026, 9, 9, 10)], feed.posts.pluck(:published_at)
  end

  private

  def source
    file_fixture("feeds/atlantic_photos/feed.xml").read
  end
end
