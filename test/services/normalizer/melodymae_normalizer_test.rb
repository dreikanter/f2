require "test_helper"

class Normalizer::MelodymaeNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/melodymae"
  end

  def processor_class
    Processor::RssProcessor
  end

  # The CDN URL in feed.xml uses &#038; for & (decoded by Nokogiri).
  # After Photon CDN host rewrite the URL points at the real melodymae.co.uk host.
  IMAGE_URL = "https://www.melodymae.co.uk/wp-content/uploads/2022/02/5372C1A6-11AE-4BCF-B225-DB49D0F928E2_1_201_a.jpeg?resize=819%2C1024&ssl=1"

  setup do
    stub_request(:get, IMAGE_URL).to_return(status: 200, body: "", headers: {})
  end

  test "#normalize should match the expected normalization result" do
    entry = feed_entry(0)

    post = Normalizer::MelodymaeNormalizer.new(entry).normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should use the entry title as content" do
    entry = feed_entry(0)

    post = Normalizer::MelodymaeNormalizer.new(entry).normalize

    assert_includes post.content, "Plus Size Alternative Retro With Belle Poque"
  end

  test "#normalize should rewrite WordPress Photon CDN image URL" do
    entry = feed_entry(0)

    post = Normalizer::MelodymaeNormalizer.new(entry).normalize

    assert_equal [IMAGE_URL], post.attachment_urls
  end

  test "#normalize should include stripped content as a comment" do
    entry = feed_entry(0)

    post = Normalizer::MelodymaeNormalizer.new(entry).normalize

    assert_equal 1, post.comments.size
    assert_includes post.comments.first, "Hello friends!"
  end

  test "#normalize should return no attachments when image check fails" do
    stub_request(:get, IMAGE_URL).to_return(status: 404)

    entry = feed_entry(0)
    post = Normalizer::MelodymaeNormalizer.new(entry).normalize

    assert_empty post.attachment_urls
  end
end
