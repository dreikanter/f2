require "test_helper"

class Processor::RssProcessorTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, url: "https://example.com/feed.xml")
  end

  def sample_rss_content
    @sample_rss_content ||= File.read(Rails.root.join("test/fixtures/files/sample_rss.xml"))
  end

  test "should parse RSS feed and create FeedEntry objects" do
    processor = Processor::RssProcessor.new(feed, sample_rss_content)
    
    entries = processor.process
    
    assert_equal 3, entries.length
    assert entries.all? { |entry| entry.is_a?(FeedEntry) }
    assert entries.all? { |entry| entry.feed == feed }
    assert entries.all? { |entry| entry.status == "pending" }
  end

  test "should extract correct data from first RSS entry" do
    processor = Processor::RssProcessor.new(feed, sample_rss_content)
    entries = processor.process
    
    first_entry = entries.first
    assert_equal "https://example.com/first-article", first_entry.external_id
    assert_equal "First Article", first_entry.title
    assert_includes first_entry.content, "first article content"
    assert_equal "https://example.com/first-article", first_entry.source_url
    assert_not_nil first_entry.published_at
    assert_not_nil first_entry.raw_data
  end

  test "should handle entries with different content structures" do
    processor = Processor::RssProcessor.new(feed, sample_rss_content)
    entries = processor.process
    
    # Second entry has content
    second_entry = entries[1]
    assert_equal "Second Article", second_entry.title
    assert_includes second_entry.content, "second article"
    
    # Third entry has no description/content
    third_entry = entries[2]
    assert_equal "Article Without Content", third_entry.title
    assert third_entry.content.blank? || third_entry.content.nil?
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

  test "should extract external_id from guid, url, or title" do
    processor = Processor::RssProcessor.new(feed, sample_rss_content)
    entries = processor.process
    
    # First entry should use URL as external_id (guid matches url)
    assert_equal "https://example.com/first-article", entries[0].external_id
    
    # Third entry should use the guid as external_id
    assert_equal "no-content-123", entries[2].external_id
  end

  test "should return empty array for invalid RSS" do
    processor = Processor::RssProcessor.new(feed, "invalid rss content")
    
    entries = processor.process
    
    assert_equal [], entries
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
    # Simulate HTTP loader output
    loader_output = {
      status: :success,
      data: sample_rss_content,
      content_type: "application/rss+xml"
    }
    
    # Process the loader output
    processor = Processor::RssProcessor.new(feed, loader_output[:data])
    entries = processor.process
    
    assert_equal 3, entries.length
    assert entries.all? { |entry| entry.valid? }
    
    # Verify all required fields are present
    entries.each do |entry|
      assert_not_nil entry.external_id
      assert_not_nil entry.title
      assert entry.title.present?
      assert_equal feed, entry.feed
    end
  end

  test "should handle entries with missing or nil fields gracefully" do
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
    
    assert_equal "Minimal Article", entry.title
    assert_equal "Minimal Article", entry.external_id # Falls back to title
    assert entry.content.blank? || entry.content.nil?
    assert entry.source_url.blank? || entry.source_url.nil?
  end
end
