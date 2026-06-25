require "test_helper"

class Processor::TelegramProcessorTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, feed_profile_key: "telegram", url: "testchannel")
  end

  def sample_html
    @sample_html ||= file_fixture("feeds/telegram/channel.html").read
  end

  def entries
    @entries ||= Processor::TelegramProcessor.new(feed, sample_html).process.entries
  end

  test "#process should create a FeedEntry per message with a data-post id" do
    assert_equal 3, entries.size
    assert entries.all? { |entry| entry.is_a?(FeedEntry) }
    assert entries.all? { |entry| entry.feed == feed }
    assert entries.all? { |entry| entry.status == "pending" }
  end

  test "#process should skip service messages without a data-post id" do
    assert_not_includes entries.map(&:uid), nil
    assert_equal %w[testchannel/1 testchannel/2 testchannel/3], entries.map(&:uid)
  end

  test "#process should store the message permalink and text html" do
    entry = entries.first

    assert_equal "https://t.me/testchannel/1", entry.raw_data["url"]
    assert_includes entry.raw_data["text_html"], "Hello"
    assert_includes entry.raw_data["text_html"], "<br>"
  end

  test "#process should extract photo URLs from the background-image style" do
    photo_entry = entries[1]

    assert_equal ["https://cdn-test.telesco.pe/file/photo2.jpg"], photo_entry.raw_data["images"]
  end

  test "#process should extract video thumbnail URLs" do
    video_entry = entries[2]

    assert_equal ["https://cdn-test.telesco.pe/file/vthumb3.jpg"], video_entry.raw_data["images"]
  end

  test "#process should use the dated time, not the video duration, for published_at" do
    video_entry = entries[2]

    assert_equal Time.utc(2026, 6, 1, 12, 10, 0), video_entry.published_at
  end
end
