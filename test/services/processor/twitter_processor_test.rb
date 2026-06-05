require "test_helper"

class Processor::TwitterProcessorTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, feed_profile_key: "twitter", url: "testuser")
  end

  def sample_html
    @sample_html ||= file_fixture("feeds/twitter/timeline.html").read
  end

  def entries
    @entries ||= Processor::TwitterProcessor.new(feed, sample_html).process
  end

  test "#process should create a FeedEntry per tweet and skip non-tweet entries" do
    assert_equal 3, entries.size
    assert entries.all? { |entry| entry.is_a?(FeedEntry) }
    assert entries.all? { |entry| entry.status == "pending" }
    assert_equal %w[1001 1002 1003], entries.map(&:uid)
  end

  test "#process should build the permalink from the relative path" do
    assert_equal "https://twitter.com/testuser/status/1001", entries.first.raw_data["url"]
  end

  test "#process should parse the tweet timestamp" do
    assert_equal Time.utc(2026, 6, 4, 18, 0, 0), entries.first.published_at
  end

  test "#process should expand t.co links in the text" do
    assert_equal "Check our docs https://developer.x.com/docs and more", entries.first.raw_data["text"]
  end

  test "#process should drop the trailing media link from the text" do
    assert_equal "Photo time", entries[1].raw_data["text"]
  end

  test "#process should extract photo media URLs" do
    assert_equal ["https://pbs.twimg.com/media/photoB.jpg"], entries[1].raw_data["images"]
  end

  test "#process should extract the video thumbnail URL" do
    assert_equal ["https://pbs.twimg.com/tweet_video_thumb/vidD.jpg"], entries[2].raw_data["images"]
  end

  test "#process should return an empty array when JSON is missing" do
    assert_equal [], Processor::TwitterProcessor.new(feed, "<html>no data</html>").process
  end
end
