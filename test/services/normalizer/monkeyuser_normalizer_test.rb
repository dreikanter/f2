require "test_helper"

class Normalizer::MonkeyuserNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/monkeyuser"
  end

  def processor_class
    Processor::RssProcessor
  end

  def stub_comic_page
    stub_request(:get, "https://www.monkeyuser.com/2025/button/")
      .to_return(status: 200, body: file_fixture("#{fixture_dir}/page.html").read)
  end

  test "#normalize should match the expected normalization result" do
    stub_comic_page
    entry = feed_entry(0)

    normalizer = Normalizer::MonkeyuserNormalizer.new(entry)
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should attach the comic image with an absolutized URL" do
    stub_comic_page
    entry = feed_entry(0)

    post = Normalizer::MonkeyuserNormalizer.new(entry).normalize

    assert_equal ["https://www.monkeyuser.com/2025/button/justabutton.png"], post.attachment_urls
  end

  test "#normalize should add the comic hovertext as a comment" do
    stub_comic_page
    entry = feed_entry(0)

    post = Normalizer::MonkeyuserNormalizer.new(entry).normalize

    assert_equal ["It's not you... it's just a button."], post.comments
  end

  test "#normalize should reject the post when the comic page is unavailable" do
    stub_request(:get, "https://www.monkeyuser.com/2025/button/").to_return(status: 500)
    entry = feed_entry(0)

    post = Normalizer::MonkeyuserNormalizer.new(entry).normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "missing_images"
    assert_empty post.attachment_urls
    assert_empty post.comments
  end

  test "#normalize should reject the post when the comic page fetch raises a network error" do
    stub_request(:get, "https://www.monkeyuser.com/2025/button/")
      .to_raise(Faraday::ConnectionFailed.new("connection refused"))
    entry = feed_entry(0)

    post = Normalizer::MonkeyuserNormalizer.new(entry).normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "missing_images"
  end

  test "#normalize should reject the post when the comic image src is a malformed URI" do
    stub_request(:get, "https://www.monkeyuser.com/2025/button/")
      .to_return(status: 200, body: <<~HTML)
        <html><body><div class="comic"><img src="/bad path/image.png" title="Alt text" /></div></body></html>
      HTML
    entry = feed_entry(0)

    post = Normalizer::MonkeyuserNormalizer.new(entry).normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "missing_images"
  end
end
