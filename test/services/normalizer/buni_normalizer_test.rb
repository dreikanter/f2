require "test_helper"

class Normalizer::BuniNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  PAGE_URL = "https://www.bunicomic.com/comic/buni-1983/".freeze

  def fixture_dir
    "feeds/buni"
  end

  def processor_class
    Processor::RssProcessor
  end

  def stub_comic_page
    stub_request(:get, PAGE_URL)
      .to_return(status: 200, body: file_fixture("#{fixture_dir}/page.html").read)
  end

  test "#normalize should match the expected normalization result" do
    stub_comic_page
    entry = feed_entry(0)

    normalizer = Normalizer::BuniNormalizer.new(entry)
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should attach the full-size comic image from the page" do
    stub_comic_page
    entry = feed_entry(0)

    post = Normalizer::BuniNormalizer.new(entry).normalize

    assert_equal ["https://www.bunicomic.com/wp-content/uploads/2026/06/2026-06-10-Buni.jpg"], post.attachment_urls
  end

  test "#normalize should use the image alt text as post content" do
    stub_comic_page
    entry = feed_entry(0)

    post = Normalizer::BuniNormalizer.new(entry).normalize

    assert_equal "To eat or not to eat that last slice - #{PAGE_URL}", post.content
  end

  test "#normalize should reject the post when the comic page is unavailable" do
    stub_request(:get, PAGE_URL).to_return(status: 404)
    entry = feed_entry(0)

    post = Normalizer::BuniNormalizer.new(entry).normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "missing_images"
  end
end
