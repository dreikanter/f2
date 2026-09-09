require "test_helper"

class Normalizer::TheycantalkNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/theycantalk"
  end

  def processor_class
    Processor::RssProcessor
  end

  def capture_log
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    yield
    io.string
  ensure
    Rails.logger = original
  end

  test "#normalize should match the expected normalization result" do
    entry = feed_entry(0)

    normalizer = Normalizer::TheycantalkNormalizer.new(entry)
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should extract the comic image as an attachment" do
    entry = feed_entry(0)

    post = Normalizer::TheycantalkNormalizer.new(entry).normalize

    assert_equal 1, post.attachment_urls.size
    assert_includes post.attachment_urls.first, "64.media.tumblr.com"
  end

  test "#normalize should use the first paragraph as content" do
    entry = feed_entry(0)

    post = Normalizer::TheycantalkNormalizer.new(entry).normalize

    assert_includes post.content, "going out"
  end

  test "#normalize should put remaining paragraphs in comments" do
    entry = feed_entry(0)

    post = Normalizer::TheycantalkNormalizer.new(entry).normalize

    # Entry has only one text paragraph so comments from paragraphs should be empty
    assert_equal [], post.comments
  end

  test "#normalize should return empty attachments for text-only entry without logging" do
    entry = create(:feed_entry, raw_data: {
      "summary" => "<p>Just a text post, no image here.</p>",
      "link" => "https://theycantalk.com/post/123"
    })

    log_output = capture_log { Normalizer::TheycantalkNormalizer.new(entry).normalize }

    refute_match(/theycantalk.*skipping attachment/, log_output)
  end

  test "#normalize should warn when figure is present but contains no img" do
    entry = create(:feed_entry, raw_data: {
      "summary" => '<div><figure class="tmblr-full"></figure></div><p>text</p>',
      "link" => "https://theycantalk.com/post/456"
    })

    log_output = capture_log { Normalizer::TheycantalkNormalizer.new(entry).normalize }

    assert_match(/\[theycantalk\].*No <img>.*skipping attachment/, log_output)
  end

  test "#normalize should warn when img src is blank" do
    entry = create(:feed_entry, raw_data: {
      "summary" => '<figure><img src="" /></figure><p>text</p>',
      "link" => "https://theycantalk.com/post/789"
    })

    log_output = capture_log { Normalizer::TheycantalkNormalizer.new(entry).normalize }

    assert_match(/\[theycantalk\].*<img>.*blank src.*skipping attachment/, log_output)
  end

  test "#normalize should include feed_id and uid in warning" do
    entry = create(:feed_entry, raw_data: {
      "summary" => "<figure></figure><p>text</p>",
      "link" => "https://theycantalk.com/post/999"
    })

    log_output = capture_log { Normalizer::TheycantalkNormalizer.new(entry).normalize }

    assert_match(/feed_id=#{entry.feed_id}/, log_output)
    assert_match(/uid=#{entry.uid}/, log_output)
  end

  test "#normalize should preserve the destination of a current TinyView link post" do
    entry = Processor::RssProcessor.new(feed, file_fixture("#{fixture_dir}/current.xml").read).process.entries.first

    post = Normalizer::TheycantalkNormalizer.new(entry).normalize

    assert_equal "murmuration (https://tinyview.com/they-can-talk/2026/08/29/murmuration) - https://theycantalk.com/post/826489748348698624", post.content
    assert_equal ["new one on tinyview: https://tinyview.com/they-can-talk/2026/08/29/murmuration"], post.comments
    assert_empty post.attachment_urls
    assert post.enqueued?
  end

  test "#normalize should preserve named and shortened links without expanding hashtags" do
    entry = build(:feed_entry, feed: feed, raw_data: {
      "link" => "https://theycantalk.com/post/123",
      "summary" => <<~HTML
        <header>Announcement</header>
        <p>Visit the <a href="https://example.com/store?a=1&amp;b=2">print shop</a>.</p>
        <p><a href="https://example.com/full-comic">https://example.com/full…</a></p>
        <p><a href="https://theycantalk.com/tagged/comic">#comic</a> <a>unlinked text</a></p>
      HTML
    })

    post = Normalizer::TheycantalkNormalizer.new(entry).normalize

    assert_equal "Announcement - https://theycantalk.com/post/123", post.content
    assert_equal [
      "Visit the print shop (https://example.com/store?a=1&b=2).",
      "https://example.com/full-comic",
      "#comic unlinked text"
    ], post.comments
  end
end
