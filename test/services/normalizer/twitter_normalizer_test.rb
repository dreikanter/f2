require "test_helper"

class Normalizer::TwitterNormalizerTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, feed_profile_key: "twitter", url: "testuser")
  end

  def posts
    @posts ||= Processor::TwitterProcessor.new(feed, file_fixture("feeds/twitter/timeline.html").read)
      .process.entries
      .map { |entry| Normalizer::TwitterNormalizer.new(entry).normalize }
  end

  test "#normalize should match the expected normalization result" do
    assert_matches_snapshot(posts.map(&:normalized_attributes), snapshot: "feeds/twitter/normalized.json")
  end

  test "#normalize should append the tweet permalink to the content" do
    assert_includes posts.first.content, "https://x.com/testuser/status/1001"
    assert_equal "1001", posts.first.uid
  end

  test "#normalize should reject a post without a full source URL" do
    html = file_fixture("feeds/twitter/timeline.html").read
      .sub("https://x.com/testuser/status/1001", "/testuser/status/1001")
    entry = Processor::TwitterProcessor.new(feed, html).process.entries.first
    post = Normalizer::TwitterNormalizer.new(entry).normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "missing_url"
    assert_equal "1001", post.uid
  end

  test "#normalize should expose photo media as attachments" do
    assert_equal ["https://pbs.twimg.com/media/photoB.jpg"], posts[1].attachment_urls
  end

  test "#normalize should expose video thumbnails as attachments" do
    assert_equal ["https://pbs.twimg.com/tweet_video_thumb/vidD.jpg"], posts[2].attachment_urls
  end

  test "#normalize should enqueue valid posts" do
    assert(posts.all? { |post| post.status == "enqueued" })
    assert(posts.all? { |post| post.validation_errors.empty? })
  end
end
