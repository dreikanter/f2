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
end
