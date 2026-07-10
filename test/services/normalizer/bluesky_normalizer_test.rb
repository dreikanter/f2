require "test_helper"

class Normalizer::BlueskyNormalizerTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, feed_profile_key: "bluesky", url: "testuser.bsky.social")
  end

  def posts
    @posts ||= Processor::BlueskyProcessor.new(feed, file_fixture("feeds/bluesky/author_feed.json").read)
      .process.entries
      .map { |entry| Normalizer::BlueskyNormalizer.new(entry).normalize }
  end

  test "#normalize should match the expected normalization result" do
    assert_matches_snapshot(posts.map(&:normalized_attributes), snapshot: "feeds/bluesky/normalized.json")
  end

  test "#normalize should append the post permalink to the content" do
    assert_includes posts.first.content, "https://bsky.app/profile/testuser.bsky.social/post/3aaa"
  end

  test "#normalize should expose embedded images as attachments" do
    assert_equal [
      "https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:testauthor/bafkphotoa",
      "https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:testauthor/bafkphotob"
    ], posts[1].attachment_urls
  end

  test "#normalize should expose video thumbnails as attachments" do
    assert_equal ["https://video.bsky.app/watch/did%3Aplc%3Atestauthor/bafkvideoc/thumbnail.jpg"], posts[2].attachment_urls
  end

  test "#normalize should expose gallery items as attachments" do
    assert_equal [
      "https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:testauthor/bafkgallerya",
      "https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:testauthor/bafkgalleryb"
    ], posts[3].attachment_urls
  end

  test "#normalize should enqueue valid posts" do
    assert(posts.all? { |post| post.status == "enqueued" })
    assert(posts.all? { |post| post.validation_errors.empty? })
  end
end
