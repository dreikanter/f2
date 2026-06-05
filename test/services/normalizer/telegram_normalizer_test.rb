require "test_helper"

class Normalizer::TelegramNormalizerTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, feed_profile_key: "telegram", url: "testchannel")
  end

  def posts
    @posts ||= Processor::TelegramProcessor.new(feed, file_fixture("feeds/telegram/channel.html").read)
      .process
      .map { |entry| Normalizer::TelegramNormalizer.new(entry).normalize }
  end

  test "#normalize should match the expected normalization result" do
    assert_matches_snapshot(posts.map(&:normalized_attributes), snapshot: "feeds/telegram/normalized.json")
  end

  test "#normalize should preserve line breaks in message text" do
    assert_includes posts.first.content, "Hello world 🚀\nSecond line"
  end

  test "#normalize should append the permalink to the content" do
    assert_includes posts.first.content, "https://t.me/testchannel/1"
  end

  test "#normalize should fall back to the permalink for a photo-only post" do
    assert_equal "https://t.me/testchannel/2", posts[1].content
  end

  test "#normalize should expose photos as attachments" do
    assert_equal ["https://cdn-test.telesco.pe/file/photo2.jpg"], posts[1].attachment_urls
  end

  test "#normalize should expose video thumbnails as attachments" do
    assert_equal ["https://cdn-test.telesco.pe/file/vthumb3.jpg"], posts[2].attachment_urls
  end

  test "#normalize should enqueue valid posts" do
    assert(posts.all? { |post| post.status == "enqueued" })
    assert(posts.all? { |post| post.validation_errors.empty? })
  end
end
