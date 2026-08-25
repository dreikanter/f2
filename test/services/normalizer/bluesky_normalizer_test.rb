require "test_helper"

class Normalizer::BlueskyNormalizerTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, feed_profile_key: "bluesky", url: "https://bsky.app/profile/testuser.bsky.social")
  end

  def posts
    @posts ||= Processor::BlueskyProcessor.new(feed, file_fixture("feeds/bluesky/author_feed.json").read)
      .process.entries
      .map { |entry| Normalizer::BlueskyNormalizer.new(entry).normalize }
  end

  def normalize(raw_data)
    url = "https://bsky.app/profile/testuser.bsky.social/post/3nnn"
    entry = FeedEntry.new(
      feed: feed,
      uid: "at://did:plc:testauthor/app.bsky.feed.post/3nnn",
      published_at: 1.hour.ago,
      status: :pending,
      raw_data: { "uid" => "at://did:plc:testauthor/app.bsky.feed.post/3nnn", "url" => url, "images" => [] }.merge(raw_data)
    )

    Normalizer::BlueskyNormalizer.new(entry).normalize
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

  test "#normalize should fold the link card into the content" do
    assert_equal(
      "Worth a read\n\nAn Article Worth Reading\nhttps://example.com/an-article - " \
      "https://bsky.app/profile/testuser.bsky.social/post/3lll",
      posts[5].content
    )
  end

  test "#normalize should build the content of a text-less post from its link card" do
    assert_equal(
      "A Post With No Words\nhttps://example.com/link-only - " \
      "https://bsky.app/profile/testuser.bsky.social/post/3mmm",
      posts[6].content
    )
  end

  test "#normalize should not repeat a link card URL already present in the text" do
    post = normalize(
      "text" => "Have a look at https://example.com/an-article",
      "link_card" => { "url" => "https://example.com/an-article", "title" => "An Article Worth Reading" }
    )

    assert_equal "Have a look at https://example.com/an-article - https://bsky.app/profile/testuser.bsky.social/post/3nnn", post.content
  end

  test "#normalize should use the link card URL alone when the card has no title" do
    post = normalize("text" => "", "link_card" => { "url" => "https://example.com/untitled" })

    assert_equal "https://example.com/untitled - https://bsky.app/profile/testuser.bsky.social/post/3nnn", post.content
  end

  test "#normalize should enqueue valid posts" do
    assert(posts.all? { |post| post.status == "enqueued" })
    assert(posts.all? { |post| post.validation_errors.empty? })
  end
end
