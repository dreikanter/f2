require "test_helper"

class PhdcomicsFeedTest < ActiveSupport::TestCase
  URL = "https://feeds.feedburner.com/PhdComics"

  test "identification should prefer the comic profile for its FeedBurner feed" do
    result = FeedProfileDetector.call(input: URL, fetched_body: source)

    assert_equal %w[phdcomics rss], result.candidates.map(&:profile_key)
  end

  test "identification should recognize the original publisher" do
    result = FeedProfileDetector.call(input: "https://www.phdcomics.com/gradfeed.php", fetched_body: source)

    assert_equal %w[phdcomics rss], result.candidates.map(&:profile_key)
  end

  test "identification should leave other FeedBurner feeds on RSS" do
    result = FeedProfileDetector.call(input: "https://feeds.feedburner.com/AnotherComic", fetched_body: source)

    assert_equal ["rss"], result.candidates.map(&:profile_key)
  end

  test "identification should reject a lookalike publisher host" do
    result = FeedProfileDetector.call(input: "https://phdcomics.com.example.org/feed", fetched_body: source)

    assert_equal ["rss"], result.candidates.map(&:profile_key)
  end

  test "preview should keep the title and comic without repeated site text" do
    preview = create(:feed_preview, feed_profile_key: "phdcomics", params: { "url" => URL })
    stub_request(:get, URL).to_return(body: source)

    FeedPreviewWorkflow.new(preview, run_id: preview.run_id).execute

    assert preview.reload.ready?
    post = preview.posts_data.sole
    assert_equal "Sample comic - https://www.phdcomics.com/comics.php?f=123", post.fetch("content")
    assert_equal ["https://images.example.com/comic2025.png"], post.fetch("attachments")
    assert_empty post.fetch("comments")
  end

  test "import should preserve the source date despite conflicting body and image dates" do
    feed = create(:feed, feed_profile_key: "phdcomics", url: URL, import_after: Time.utc(2021, 10, 24))
    stub_request(:get, URL).to_return(body: source)

    FeedRefreshWorkflow.new(feed).execute

    assert_equal ["sample:comic"], feed.feed_entries.pluck(:uid)
    assert_equal [Time.utc(2021, 10, 25, 9, 9, 47)], feed.posts.pluck(:published_at)
  end

  test "import should apply the cutoff to the source date" do
    feed = create(:feed, feed_profile_key: "phdcomics", url: URL, import_after: Time.utc(2022, 1, 1))
    stub_request(:get, URL).to_return(body: source)

    FeedRefreshWorkflow.new(feed).execute

    assert_empty feed.posts
  end

  private

  def source
    file_fixture("feeds/phdcomics/feed.xml").read
  end
end
