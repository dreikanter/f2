require "test_helper"

class Processor::AerostatProcessorTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, url: "https://aerostatbg.ru/rss.xml")
  end

  def feed_xml
    @feed_xml ||= file_fixture("feeds/aerostat/feed.xml").read
  end

  def processor
    Processor::AerostatProcessor.new(feed, feed_xml)
  end

  test "#process should parse feed and create FeedEntry objects" do
    entries = processor.process.entries

    assert_equal 2, entries.length
    assert entries.all? { |e| e.is_a?(FeedEntry) }
    assert entries.all? { |e| e.feed == feed }
    assert entries.all? { |e| e.status == "pending" }
  end

  test "#process should extract itunes_image into raw_data" do
    entry = processor.process.entries.first

    assert_equal(
      "https://aerostatbg.ru/sites/default/files/styles/rss_image/public/releases/1094.jpg?itok=IpSaPXdB",
      entry.raw_data["itunes_image"]
    )
  end

  test "#process should extract enclosure_url into raw_data" do
    entry = processor.process.entries.first

    assert_equal "https://aerostats.getmobileup.com/music/1094.mp3", entry.raw_data["enclosure_url"]
  end

  test "#process should warn when entry is missing enclosure_url" do
    xml_without_enclosure = feed_xml.sub(/<enclosure[^>]*\/>/, "")
    proc_no_enc = Processor::AerostatProcessor.new(feed, xml_without_enclosure)
    warned_messages = []

    Rails.logger.stub(:warn, ->(msg) { warned_messages << msg }) do
      proc_no_enc.process
    end

    assert warned_messages.any? { |m| m.match?(/missing enclosure_url/) },
           "Expected a warning about missing enclosure_url"
  end

  test "#process should warn when entry is missing itunes_image" do
    xml_without_image = feed_xml.gsub(/<itunes:image href="[^"]*"\/>/, "")
    proc_no_img = Processor::AerostatProcessor.new(feed, xml_without_image)
    warned_messages = []

    Rails.logger.stub(:warn, ->(msg) { warned_messages << msg }) do
      proc_no_img.process
    end

    assert warned_messages.any? { |m| m.match?(/missing itunes_image/) },
           "Expected a warning about missing itunes_image"
  end
end
