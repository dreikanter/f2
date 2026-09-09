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
    stub_request(:get, "https://www.litterboxcomics.com/sample-comic-one/")
      .to_return(status: 200, body: file_fixture("feeds/litterbox/page.html").read)
    stub_request(:get, "https://www.litterboxcomics.com/sample-comic-one-bonus/")
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

    assert_equal "Sample Comic One - https://www.litterboxcomics.com/sample-comic-one/", post.content
  end

  test "#normalize should include the bonus panel as a comment" do
    entry = feed_entry(0)

    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_equal ["Bonus panel: https://www.litterboxcomics.com/wp-content/uploads/sample-comic-one-bonus.png"], post.comments
  end

  test "#normalize should fall back to content HTML image when page has no swiper" do
    entry = feed_entry(0)

    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_includes post.attachment_urls, "https://www.litterboxcomics.com/wp-content/uploads/sample-comic-one.png"
  end

  test "#normalize should use swiper images when page has swiper-wrapper" do
    stub_request(:get, "https://www.litterboxcomics.com/sample-comic-one/")
      .to_return(status: 200, body: file_fixture("feeds/litterbox/page_swiper.html").read)

    entry = feed_entry(0)
    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_equal [
      "https://www.litterboxcomics.com/wp-content/uploads/sample-comic-one-1.png",
      "https://www.litterboxcomics.com/wp-content/uploads/sample-comic-one-2.png"
    ], post.attachment_urls
  end

  test "#normalize should handle bonus page fetch failure gracefully" do
    stub_request(:get, "https://www.litterboxcomics.com/sample-comic-one-bonus/")
      .to_raise(HttpClient::Error)

    entry = feed_entry(0)
    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_equal [], post.comments
  end

  test "#normalize should keep all four images in the current Absolute Cinema post" do
    entry = current_entries.find { |item| item.raw_data["title"] == "Absolute Cinema" }
    stub_request(:get, entry.raw_data["link"]).to_return(body: "<article></article>")
    stub_request(:get, "https://www.litterboxcomics.com/absolute-cinema-meme-bonus/").to_return(status: 404)

    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_equal %w[
      litterbox-absolute-cinema-meme.png
      absolute-parenting-meme.png
      absolute-litterbox-meme.png
      absolute-cinema-meme-BLANK.png
    ], post.attachment_urls.map { |url| File.basename(URI.parse(url).path) }
    assert post.enqueued?
  end

  test "#normalize should retain the current Patreon bonus link when the public bonus page is absent" do
    entry = current_entries.find { |item| item.raw_data["title"] == "Food Court (Remastered)" }
    stub_request(:get, entry.raw_data["link"]).to_return(body: "<article></article>")
    stub_request(:get, "https://www.litterboxcomics.com/food-court2-bonus/").to_return(status: 404)

    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_equal ["Bonus panel: https://www.patreon.com/litterboxcomics/posts/comic-food-court-167153444"], post.comments
    assert_equal 1, post.attachment_urls.size
  end

  test "#normalize should reject standalone bonus posts without fetching another bonus" do
    ["https://www.litterboxcomics.com/sample-bonus/", "https://www.litterboxcomics.com/sample-bonus?ref=rss"].each do |url|
      entry = build(:feed_entry, feed: feed, raw_data: { "link" => url, "title" => "Sample Bonus" })

      post = Normalizer::LitterboxNormalizer.new(entry).normalize

      assert post.rejected?
      assert_includes post.validation_errors, "bonus"
      assert_empty post.comments
    end

    assert_not_requested :get, /sample-bonus/
  end

  test "#normalize should preserve every RSS image if the article fetch fails" do
    entry = current_entries.find { |item| item.raw_data["title"] == "Absolute Cinema" }
    stub_request(:get, entry.raw_data["link"]).to_raise(HttpClient::Error)
    stub_request(:get, "https://www.litterboxcomics.com/absolute-cinema-meme-bonus/").to_return(status: 404)

    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_equal 4, post.attachment_urls.size
    assert post.enqueued?
  end

  def current_entries
    Processor::RssProcessor.new(feed, file_fixture("#{fixture_dir}/current.xml").read).process.entries
  end

  test "#normalize should preserve all eight carousel panels and the bonus from feeder's fixture" do
    entry = Processor::RssProcessor.new(feed, file_fixture("#{fixture_dir}/legacy_slides.xml").read).process.entries.first
    expected = JSON.parse(file_fixture("#{fixture_dir}/legacy_slides.json").read)
    stub_request(:get, "https://www.litterboxcomics.com/worlds-collide/")
      .to_return(body: file_fixture("#{fixture_dir}/legacy_slides.html").read)
    stub_request(:get, "https://www.litterboxcomics.com/worlds-collide-bonus/")
      .to_return(body: '<meta property="og:image" content="https://www.litterboxcomics.com/wp-content/uploads/2021/07/xover-bonus.png">')

    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_equal expected.fetch("attachments"), post.attachment_urls
    assert_equal expected.fetch("comments"), post.comments
  end
end
