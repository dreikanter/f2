require "test_helper"

class Processor::BlueskyProcessorTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, feed_profile_key: "bluesky", url: "testuser.bsky.social")
  end

  def sample_json
    @sample_json ||= file_fixture("feeds/bluesky/author_feed.json").read
  end

  def entries
    @entries ||= Processor::BlueskyProcessor.new(feed, sample_json).process.entries
  end

  test "#process should create a FeedEntry per own post and skip reposts and replies" do
    assert_equal 5, entries.size
    assert entries.all? { |entry| entry.is_a?(FeedEntry) }
    assert entries.all? { |entry| entry.status == "pending" }
    assert_equal %w[3aaa 3bbb 3ccc 3ddd 3eee], entries.map { |entry| entry.uid.split("/").last }
  end

  test "#process should use the at:// URI as the uid" do
    assert_equal "at://did:plc:testauthor/app.bsky.feed.post/3aaa", entries.first.uid
  end

  test "#process should build the permalink from the handle and rkey" do
    assert_equal "https://bsky.app/profile/testuser.bsky.social/post/3aaa", entries.first.raw_data["url"]
  end

  test "#process should parse the post timestamp" do
    assert_equal Time.utc(2026, 6, 4, 18, 0, 0), entries.first.published_at
  end

  test "#process should expand truncated link text from the facets" do
    assert_equal "Read our docs https://docs.bsky.app/get-started today", entries.first.raw_data["text"]
  end

  test "#process should expand facet links addressed past multibyte characters" do
    prefix = "🦋 look "
    display = "example.com/a..."
    payload = {
      "feed" => [
        {
          "post" => {
            "uri" => "at://did:plc:testauthor/app.bsky.feed.post/3hhh",
            "author" => { "did" => "did:plc:testauthor", "handle" => "testuser.bsky.social" },
            "record" => {
              "createdAt" => "2026-06-04T18:00:00.000Z",
              "text" => "#{prefix}#{display} now",
              "facets" => [
                {
                  "features" => [{ "$type" => "app.bsky.richtext.facet#link", "uri" => "https://example.com/article" }],
                  "index" => { "byteStart" => prefix.bytesize, "byteEnd" => prefix.bytesize + display.bytesize }
                }
              ]
            }
          }
        }
      ]
    }

    result = Processor::BlueskyProcessor.new(feed, payload.to_json).process
    assert_equal "🦋 look https://example.com/article now", result.entries.first.raw_data["text"]
  end

  test "#process should keep the original text when facet offsets are out of range" do
    payload = {
      "feed" => [
        {
          "post" => {
            "uri" => "at://did:plc:testauthor/app.bsky.feed.post/3iii",
            "author" => { "did" => "did:plc:testauthor", "handle" => "testuser.bsky.social" },
            "record" => {
              "createdAt" => "2026-06-04T18:00:00.000Z",
              "text" => "short",
              "facets" => [
                {
                  "features" => [{ "$type" => "app.bsky.richtext.facet#link", "uri" => "https://example.com" }],
                  "index" => { "byteStart" => 2, "byteEnd" => 99 }
                }
              ]
            }
          }
        }
      ]
    }

    result = Processor::BlueskyProcessor.new(feed, payload.to_json).process
    assert_equal "short", result.entries.first.raw_data["text"]
  end

  test "#process should extract fullsize image URLs" do
    assert_equal [
      "https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:testauthor/bafkphotoa",
      "https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:testauthor/bafkphotob"
    ], entries[1].raw_data["images"]
  end

  test "#process should extract the video thumbnail URL" do
    assert_equal ["https://video.bsky.app/watch/did%3Aplc%3Atestauthor/bafkvideoc/thumbnail.jpg"], entries[2].raw_data["images"]
  end

  test "#process should extract gallery item URLs" do
    assert_equal [
      "https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:testauthor/bafkgallerya",
      "https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:testauthor/bafkgalleryb"
    ], entries[3].raw_data["images"]
  end

  test "#process should extract images from a quote post with media" do
    assert_equal ["https://cdn.bsky.app/img/feed_fullsize/plain/did:plc:testauthor/bafkquotepic"], entries[4].raw_data["images"]
  end

  test "#process should fall back to the DID permalink when the handle did not resolve" do
    payload = {
      "feed" => [
        {
          "post" => {
            "uri" => "at://did:plc:testauthor/app.bsky.feed.post/3jjj",
            "author" => { "did" => "did:plc:testauthor", "handle" => "handle.invalid" },
            "record" => { "createdAt" => "2026-06-04T18:00:00.000Z", "text" => "hello" }
          }
        }
      ]
    }

    result = Processor::BlueskyProcessor.new(feed, payload.to_json).process
    assert_equal "https://bsky.app/profile/did:plc:testauthor/post/3jjj", result.entries.first.raw_data["url"]
  end

  test "#process should skip posts without a timestamp" do
    payload = {
      "feed" => [
        {
          "post" => {
            "uri" => "at://did:plc:testauthor/app.bsky.feed.post/3kkk",
            "author" => { "did" => "did:plc:testauthor", "handle" => "testuser.bsky.social" },
            "record" => { "text" => "no createdAt" }
          }
        }
      ]
    }

    result = Processor::BlueskyProcessor.new(feed, payload.to_json).process
    assert_equal [], result.entries
    assert result.recognized?
  end

  test "#process should skip feed items that are not objects" do
    result = Processor::BlueskyProcessor.new(feed, '{"feed":["str",42,null]}').process

    assert_equal [], result.entries
    assert result.recognized?
  end

  test "#process should recognize a real author feed payload" do
    assert Processor::BlueskyProcessor.new(feed, sample_json).process.recognized?
  end

  test "#process should recognize a feed with no posts" do
    result = Processor::BlueskyProcessor.new(feed, '{"feed":[]}').process

    assert result.recognized?
    assert_equal [], result.entries
  end

  test "#process should not recognize invalid JSON" do
    assert_not Processor::BlueskyProcessor.new(feed, "{not json}").process.recognized?
  end

  test "#process should not recognize JSON without a feed array" do
    assert_not Processor::BlueskyProcessor.new(feed, '{"posts":[]}').process.recognized?
    assert_not Processor::BlueskyProcessor.new(feed, '{"feed":"nope"}').process.recognized?
    assert_not Processor::BlueskyProcessor.new(feed, "[]").process.recognized?
  end
end
