require "test_helper"

class Processor::RssProcessorTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, url: "https://example.com/feed.xml")
  end

  def sample_rss_content
    @sample_rss_content ||= file_fixture("feeds/rss/feed.xml").read
  end

  test "#process should parse RSS feed and create FeedEntry objects" do
    processor = Processor::RssProcessor.new(feed, sample_rss_content)
    entries = processor.process

    assert_equal 3, entries.length
    assert entries.all? { |entry| entry.is_a?(FeedEntry) }
    assert entries.all? { |entry| entry.feed == feed }
    assert entries.all? { |entry| entry.status == "pending" }
    assert entries.all? { |entry| entry.valid? }

    entries_snapshot = entries.map do |entry|
      entry.as_json(only: %i[uid status published_at raw_data])
    end

    assert_matches_snapshot(entries_snapshot, snapshot: "feeds/rss/entries.json")
  end

  test "#process should raise error for invalid RSS" do
    processor = Processor::RssProcessor.new(feed, "invalid rss content")

    assert_raises(Feedjira::NoParserAvailable) do
      processor.process
    end
  end

  test "#process should return empty array for RSS without entries" do
    empty_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Empty Feed</title>
          <description>A feed with no items</description>
        </channel>
      </rss>
    RSS

    processor = Processor::RssProcessor.new(feed, empty_rss)
    entries = processor.process

    assert_equal [], entries
  end

  def image_feed_content
    @image_feed_content ||= file_fixture("feeds/rss/feed_with_images.xml").read
  end

  test "#process should extract RSS enclosure as typed enclosure" do
    entries = Processor::RssProcessor.new(feed, image_feed_content).process

    enclosures = entries.find { |e| e.raw_data["title"] == "Spiral Galaxy Close-Up" }.raw_data["enclosures"]
    assert_equal [{ "url" => "https://example.com/uploads/2024/09/spiral-galaxy.jpg", "type" => "image/jpeg" }], enclosures
  end

  test "#process should extract media:thumbnail with nil type" do
    entries = Processor::RssProcessor.new(feed, image_feed_content).process

    enclosures = entries.find { |e| e.raw_data["title"] == "Nebula Formation" }.raw_data["enclosures"]
    assert_equal [{ "url" => "https://example.com/uploads/2024/09/nebula-thumb.jpg", "type" => nil }], enclosures
  end

  test "#process should extract all media:content elements including non-image types" do
    entries = Processor::RssProcessor.new(feed, image_feed_content).process

    enclosures = entries.find { |e| e.raw_data["title"] == "Planetary Surface" }.raw_data["enclosures"]
    assert_equal 3, enclosures.length
    assert_includes enclosures, { "url" => "https://example.com/uploads/2024/09/surface-full.jpg", "type" => "image/jpeg" }
    assert_includes enclosures, { "url" => "https://example.com/uploads/2024/09/surface-thumb.jpg", "type" => "image/jpeg" }
    assert_includes enclosures, { "url" => "https://example.com/uploads/2024/09/surface-timelapse.mp4", "type" => "video/mp4" }
  end

  test "#process should store empty enclosures for entries with no media" do
    entries = Processor::RssProcessor.new(feed, image_feed_content).process

    enclosures = entries.find { |e| e.raw_data["title"] == "Mission Update" }.raw_data["enclosures"]
    assert_equal [], enclosures
  end

  test "#process should handle entries without id or url" do
    minimal_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Minimal Feed</title>
          <item>
            <title>Minimal Article</title>
          </item>
        </channel>
      </rss>
    RSS

    processor = Processor::RssProcessor.new(feed, minimal_rss)
    entries = processor.process

    assert_equal 1, entries.length
    entry = entries.first
    assert_nil entry.uid
    assert_not entry.valid?
  end
end
