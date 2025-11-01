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
