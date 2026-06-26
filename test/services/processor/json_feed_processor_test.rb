require "test_helper"

class Processor::JsonFeedProcessorTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, url: "https://example.com/feed.json")
  end

  def sample_content
    @sample_content ||= file_fixture("feeds/json_feed/feed.json").read
  end

  def entries
    @entries ||= Processor::JsonFeedProcessor.new(feed, sample_content).process.entries
  end

  test "#process should parse JSON Feed and create FeedEntry objects" do
    assert_equal 3, entries.length
    assert entries.all? { |entry| entry.is_a?(FeedEntry) }
    assert entries.all? { |entry| entry.feed == feed }
    assert entries.all? { |entry| entry.status == "pending" }
    assert entries.all?(&:valid?)

    snapshot = entries.map { |entry| entry.as_json(only: %i[uid status published_at raw_data]) }
    assert_matches_snapshot(snapshot, snapshot: "feeds/json_feed/entries.json")
  end

  test "#process should prefer content_html and extract inline image fields" do
    first = entries.first

    assert_equal "https://example.com/first-post", first.uid
    assert_equal "<p>Hello, world! Here is an <img src=\"https://example.com/inline.jpg\"> inline image.</p>", first.raw_data["content"]
    assert_equal ["news", "intro"], first.raw_data["categories"]
  end

  test "#process should fall back to content_text when there is no HTML" do
    second = entries.find { |entry| entry.uid == "https://example.com/second-post" }

    assert_equal "This is a plain text post with no HTML markup.", second.raw_data["content"]
    assert_equal "https://other.example.org/article", second.raw_data["external_url"]
    assert_equal "John Writer", second.raw_data["author"]
  end

  test "#process should fold image, banner_image, and image attachments into enclosures" do
    photo = entries.find { |entry| entry.uid == "https://example.com/photo-post" }

    assert_equal [
      { "url" => "https://example.com/main-photo.jpg", "type" => nil },
      { "url" => "https://example.com/banner.jpg", "type" => nil },
      { "url" => "https://example.com/audio.m4a", "type" => "audio/x-m4a" },
      { "url" => "https://example.com/gallery.png", "type" => "image/png" }
    ], photo.raw_data["enclosures"]
  end

  test "#process should read the top-level authors list for the first item" do
    first = entries.first

    assert_equal "Jane Author", first.raw_data["author"]
  end

  test "#process should recognize a valid JSON Feed" do
    assert Processor::JsonFeedProcessor.new(feed, sample_content).process.recognized?
  end

  test "#process should recognize an empty feed that carries a version and title" do
    body = '{"version":"https://jsonfeed.org/version/1.1","title":"Empty","items":[]}'

    result = Processor::JsonFeedProcessor.new(feed, body).process
    assert_empty result.entries
    assert result.recognized?
  end

  test "#process should not recognize JSON that lacks the version marker" do
    body = '{"title":"Not a feed","items":[{"id":"1","url":"https://example.com/1"}]}'

    assert_not Processor::JsonFeedProcessor.new(feed, body).process.recognized?
  end

  test "#process should raise on unparseable JSON" do
    assert_raises(JSON::ParserError) do
      Processor::JsonFeedProcessor.new(feed, "not json at all").process
    end
  end

  test "#process should default a missing date_published to now" do
    body = '{"version":"https://jsonfeed.org/version/1.1","title":"Feed","items":[{"id":"x","url":"https://example.com/x","content_text":"hi"}]}'

    freeze_time do
      entry = Processor::JsonFeedProcessor.new(feed, body).process.entries.first
      assert_equal Time.current, entry.published_at
      assert_nil entry.raw_data["published"]
    end
  end

  test "#process should fall back to url when id is missing" do
    body = '{"version":"https://jsonfeed.org/version/1.1","title":"Feed","items":[{"url":"https://example.com/no-id","content_text":"hi"}]}'

    entry = Processor::JsonFeedProcessor.new(feed, body).process.entries.first
    assert_equal "https://example.com/no-id", entry.uid
  end

  test "#process should coerce a numeric id to a string uid" do
    body = '{"version":"https://jsonfeed.org/version/1.1","title":"Feed","items":[{"id":42,"url":"https://example.com/42","content_text":"hi"}]}'

    entry = Processor::JsonFeedProcessor.new(feed, body).process.entries.first
    assert_equal "42", entry.uid
  end

  test "#process should read a single author object (JSON Feed 1.0)" do
    body = '{"version":"https://jsonfeed.org/version/1","title":"Feed","items":[{"id":"1","url":"https://example.com/1","author":{"name":"Solo Author"},"content_text":"hi"}]}'

    entry = Processor::JsonFeedProcessor.new(feed, body).process.entries.first
    assert_equal "Solo Author", entry.raw_data["author"]
  end

  test "#process should inherit the top-level author for an item without one (JSON Feed 1.0)" do
    body = '{"version":"https://jsonfeed.org/version/1","title":"Feed","author":{"name":"Feed Owner"},"items":[{"id":"1","url":"https://example.com/1","content_text":"hi"}]}'

    entry = Processor::JsonFeedProcessor.new(feed, body).process.entries.first
    assert_equal "Feed Owner", entry.raw_data["author"]
  end

  test "#process should prefer an item's own author over the feed-level one" do
    body = '{"version":"https://jsonfeed.org/version/1","title":"Feed","author":{"name":"Feed Owner"},"items":[{"id":"1","url":"https://example.com/1","author":{"name":"Item Author"},"content_text":"hi"}]}'

    entry = Processor::JsonFeedProcessor.new(feed, body).process.entries.first
    assert_equal "Item Author", entry.raw_data["author"]
  end
end
