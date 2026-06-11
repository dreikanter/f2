require "test_helper"

class Normalizer::LitterboxNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/litterbox"
  end

  def processor_class
    Processor::RssProcessor
  end

  setup do
    stub_request(:get, "https://www.litterboxcomics.com/dark-chocolate/")
      .to_return(status: 200, body: file_fixture("feeds/litterbox/page.html").read)
    stub_request(:get, "https://www.litterboxcomics.com/dark-chocolate-bonus/")
      .to_return(status: 200, body: file_fixture("feeds/litterbox/bonus_page.html").read)
  end

  test "#normalize should match the expected normalization result" do
    entry = feed_entry(0)

    normalizer = Normalizer::LitterboxNormalizer.new(entry)
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should use the entry title as content" do
    entry = feed_entry(0)

    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_equal "Dark Chocolate - https://www.litterboxcomics.com/dark-chocolate/", post.content
  end

  test "#normalize should include the bonus panel as a comment" do
    entry = feed_entry(0)

    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_equal ["Bonus panel: https://www.litterboxcomics.com/wp-content/uploads/2026/06/dark-chocolate-bonus.png"], post.comments
  end

  test "#normalize should fall back to content HTML image when page has no swiper" do
    entry = feed_entry(0)

    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_includes post.attachment_urls, "https://i0.wp.com/www.litterboxcomics.com/wp-content/uploads/2026/06/dark-chocolate.png?resize=1000%2C1249&ssl=1"
  end

  test "#normalize should use swiper images when page has swiper-wrapper" do
    stub_request(:get, "https://www.litterboxcomics.com/dark-chocolate/")
      .to_return(status: 200, body: file_fixture("feeds/litterbox/page_swiper.html").read)

    entry = feed_entry(0)
    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_equal [
      "https://www.litterboxcomics.com/wp-content/uploads/2026/06/dark-chocolate-1.png",
      "https://www.litterboxcomics.com/wp-content/uploads/2026/06/dark-chocolate-2.png"
    ], post.attachment_urls
  end

  test "#normalize should reject bonus posts with 'bonus' validation error" do
    entry = feed_entry(0)
    entry.raw_data["link"] = "https://www.litterboxcomics.com/dark-chocolate-bonus/"
    # setup already stubs dark-chocolate-bonus/ for the article fetch;
    # stub the bonus-of-bonus URL that will be derived
    stub_request(:get, "https://www.litterboxcomics.com/dark-chocolate-bonus-bonus/")
      .to_return(status: 404, body: "")

    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_includes post.validation_errors, "bonus"
    assert post.rejected?
  end

  test "#normalize should handle bonus page fetch failure gracefully" do
    stub_request(:get, "https://www.litterboxcomics.com/dark-chocolate-bonus/")
      .to_raise(HttpClient::Error)

    entry = feed_entry(0)
    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_equal [], post.comments
  end
end
