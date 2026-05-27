require "test_helper"

class Processor::YoutubeProcessorTest < ActiveSupport::TestCase
  CHANNEL_ID = "UCMCgOm8GZkHp8zJ6l7_hIuA"
  FIRST_VIDEO_ID = "CNJL4GsSrcc"

  def feed
    @feed ||= create(:feed, url: "https://www.youtube.com/feeds/videos.xml?channel_id=#{CHANNEL_ID}")
  end

  def sample_feed_xml
    @sample_feed_xml ||= file_fixture("feeds/youtube/feed.xml").read
  end

  test "#process should parse YouTube feed and create FeedEntry objects" do
    processor = Processor::YoutubeProcessor.new(feed, sample_feed_xml)
    entries = processor.process

    assert_equal 15, entries.length
    assert entries.all? { |entry| entry.is_a?(FeedEntry) }
    assert entries.all? { |entry| entry.feed == feed }
    assert entries.all? { |entry| entry.status == "pending" }
  end

  test "#process should set uid from video id" do
    processor = Processor::YoutubeProcessor.new(feed, sample_feed_xml)
    entries = processor.process

    assert_equal "yt:video:#{FIRST_VIDEO_ID}", entries.first.uid
  end

  test "#process should include thumbnail in raw_data" do
    processor = Processor::YoutubeProcessor.new(feed, sample_feed_xml)
    entry = processor.process.first
    entry.save!

    assert_equal "https://i4.ytimg.com/vi/#{FIRST_VIDEO_ID}/hqdefault.jpg", entry.raw_data["thumbnail"]
  end

  test "#process should include video URL in raw_data" do
    processor = Processor::YoutubeProcessor.new(feed, sample_feed_xml)
    entry = processor.process.first
    entry.save!

    assert_equal "https://www.youtube.com/watch?v=#{FIRST_VIDEO_ID}", entry.raw_data["url"]
  end
end
