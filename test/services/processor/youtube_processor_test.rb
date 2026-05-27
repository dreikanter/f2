require "test_helper"

class Processor::YoutubeProcessorTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, url: "https://www.youtube.com/feeds/videos.xml?channel_id=UC_x5XG1OV2P6uZZ5FSM9Ttw")
  end

  def sample_feed_xml
    @sample_feed_xml ||= file_fixture("feeds/youtube/feed.xml").read
  end

  test "#process should parse YouTube feed and create FeedEntry objects" do
    processor = Processor::YoutubeProcessor.new(feed, sample_feed_xml)
    entries = processor.process

    assert_equal 2, entries.length
    assert entries.all? { |entry| entry.is_a?(FeedEntry) }
    assert entries.all? { |entry| entry.feed == feed }
    assert entries.all? { |entry| entry.status == "pending" }
  end

  test "#process should set uid from video id" do
    processor = Processor::YoutubeProcessor.new(feed, sample_feed_xml)
    entries = processor.process

    assert_equal "yt:video:dQw4w9WgXcQ", entries.first.uid
  end

  test "#process should include thumbnail in raw_data" do
    processor = Processor::YoutubeProcessor.new(feed, sample_feed_xml)
    entry = processor.process.first
    entry.save!

    assert_equal "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg", entry.raw_data["thumbnail"]
  end

  test "#process should include video URL in raw_data" do
    processor = Processor::YoutubeProcessor.new(feed, sample_feed_xml)
    entry = processor.process.first
    entry.save!

    assert_equal "https://www.youtube.com/watch?v=dQw4w9WgXcQ", entry.raw_data["url"]
  end
end
