require "test_helper"

class Processor::PodcastProcessorTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, feed_profile_key: "podcast")
  end

  def feed_xml
    @feed_xml ||= file_fixture("feeds/podcast/feed.xml").read
  end

  def processor
    Processor::PodcastProcessor.new(feed, feed_xml)
  end

  test "#process should parse feed and create FeedEntry objects" do
    entries = processor.process.entries

    assert_equal 3, entries.length
    assert entries.all? { |e| e.is_a?(FeedEntry) }
    assert entries.all? { |e| e.feed == feed }
    assert entries.all? { |e| e.status == "pending" }
  end

  test "#process should extract itunes_image into raw_data" do
    entry = processor.process.entries.first

    assert_equal "https://signalpath.example.fm/art/ep42.jpg", entry.raw_data["itunes_image"]
  end

  test "#process should fall back to the channel cover when an episode has no image" do
    entry = processor.process.entries.second

    assert_equal "https://signalpath.example.fm/art/cover.jpg", entry.raw_data["itunes_image"]
  end

  test "#process should extract enclosure_url into raw_data" do
    entry = processor.process.entries.first

    assert_equal "https://cdn.example.fm/signalpath/ep42.mp3", entry.raw_data["enclosure_url"]
  end

  test "#process should leave itunes_image nil when neither episode nor channel has one" do
    xml_without_images = feed_xml.gsub(/<itunes:image[^>]*\/>\n?\s*/, "")
    entry = Processor::PodcastProcessor.new(feed, xml_without_images).process.entries.first

    assert_nil entry.raw_data["itunes_image"]
  end
end
