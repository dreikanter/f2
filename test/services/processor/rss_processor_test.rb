require "test_helper"

class Processor::RssProcessorTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, url: "https://example.com/feed.xml")
  end

  def sample_rss_content
    @sample_rss_content ||= File.read(Rails.root.join("test/fixtures/feeds/rss/feed.xml"))
  end

  test "should parse RSS feed and create FeedEntry objects" do
    processor = Processor::RssProcessor.new(feed, sample_rss_content)

    entries = processor.process

    assert_equal 3, entries.length
    assert entries.all? { |entry| entry.is_a?(FeedEntry) }
    assert entries.all? { |entry| entry.feed == feed }
    assert entries.all? { |entry| entry.status == "pending" }
  end

  test "should extract uid from guid or url" do
    processor = Processor::RssProcessor.new(feed, sample_rss_content)
    entries = processor.process

    # First entry should use URL as uid (guid matches url)
    assert_equal "https://example.com/first-article", entries[0].uid

    # Third entry should use the guid as uid
    assert_equal "no-content-123", entries[2].uid
  end

  test "should store raw entry data as JSON" do
    processor = Processor::RssProcessor.new(feed, sample_rss_content)
    entries = processor.process

    first_entry = entries.first
    raw_data = first_entry.raw_data

    assert raw_data.is_a?(Hash)
    assert_equal "First Article", raw_data["title"]
    assert_equal "https://example.com/first-article", raw_data["url"]
    assert_not_nil raw_data["published"]
    assert_not_nil raw_data["author"]
  end

  test "should raise error for invalid RSS" do
    processor = Processor::RssProcessor.new(feed, "invalid rss content")

    assert_raises(Feedjira::NoParserAvailable) do
      processor.process
    end
  end

  test "should return empty array for RSS without entries" do
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

  test "integration: should work with HTTP loader output" do
    loader_output = {
      status: :success,
      data: sample_rss_content,
      content_type: "application/rss+xml"
    }

    processor = Processor::RssProcessor.new(feed, loader_output[:data])
    entries = processor.process

    assert_equal 3, entries.length

    entries.each do |entry|
      assert_equal feed, entry.feed
    end

    valid_entries = entries.select(&:valid?)
    assert valid_entries.length >= 1
  end

  test "should handle entries without id or url" do
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
