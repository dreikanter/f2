require "test_helper"

class TumblrFeedTest < ActiveSupport::TestCase
  URL = "https://sample.tumblr.com/rss"

  test "identification should prefer Tumblr over RSS for a syndicated custom domain" do
    result = FeedProfileDetector.call(input: "https://feeds.example.org/comic", fetched_body: source)

    assert_equal %w[tumblr rss], result.candidates.map(&:profile_key)
    assert_not ProfileMatcher::TumblrProfileMatcher.new(URL, "<html>Tumblr</html>").match?
  end

  test "normalization should keep every panel caption and accessible image description" do
    feed = build(:feed, feed_profile_key: "tumblr", url: URL)
    stub_request(:get, URL).to_return(body: source)
    entry = feed.processor_instance(feed.loader_instance.load).process.entries.first
    post = feed.normalizer_instance(entry).normalize

    assert_equal "Sample strip - https://sample.tumblr.com/post/123", post.content
    assert_equal ["https://images.example.com/first-large.png", "https://images.example.com/second.png"], post.attachment_urls
    assert_equal ["Read the bonus (https://example.org/bonus).", "First panel description"], post.comments
    assert post.enqueued?
  end

  test "preview should preserve an external comic link without inventing an image" do
    preview = create(:feed_preview, feed_profile_key: "tumblr", params: { "url" => URL })
    stub_request(:get, URL).to_return(body: source)

    FeedPreviewWorkflow.new(preview, run_id: preview.run_id).execute

    assert preview.reload.ready?
    post = preview.posts_data.find { |item| item["source_url"] == "https://sample.tumblr.com/post/124" }
    assert_includes post.fetch("content"), "External comic (https://example.org/comic)"
    assert_equal [], post.fetch("attachments")
  end

  test "import should apply the cutoff to source dates and preserve new panels" do
    feed = create(:feed, :enabled, feed_profile_key: "tumblr", url: URL,
                  import_after: Time.utc(2026, 9, 9, 12))
    stub_request(:get, URL).to_return(body: source)

    FeedRefreshWorkflow.new(feed).execute

    assert_equal ["https://sample.tumblr.com/post/124"], feed.feed_entries.pluck(:uid)
    assert_equal 1, feed.posts.count
  end

  private

  def source
    file_fixture("feeds/tumblr/feed.xml").read
  end
end
