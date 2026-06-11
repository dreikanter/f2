require "test_helper"

class Normalizer::PluralisticNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/pluralistic"
  end

  def processor_class
    Processor::RssProcessor
  end

  setup do
    stub_request(:get, "https://pluralistic.net/2026/06/11/lapsarianism/")
      .to_return(status: 200, body: file_fixture("feeds/pluralistic/page.html").read)
  end

  test "#normalize should match the expected normalization result" do
    entry = feed_entry(0)

    normalizer = Normalizer::PluralisticNormalizer.new(entry)
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should rewrite WordPress Photon CDN image URL to direct URL" do
    entry = feed_entry(0)

    post = Normalizer::PluralisticNormalizer.new(entry).normalize

    assert_equal ["https://craphound.com/images/11Jun2026.jpg?w=840&ssl=1"], post.attachment_urls
  end

  test "#normalize should use entry title as content" do
    entry = feed_entry(0)

    post = Normalizer::PluralisticNormalizer.new(entry).normalize

    assert_match "The world has moved on", post.content
  end

  test "#normalize should fall back to inherited defaults when page fetch fails" do
    stub_request(:get, "https://pluralistic.net/2026/06/11/lapsarianism/")
      .to_return(status: 503, body: "")

    entry = feed_entry(0)

    post = Normalizer::PluralisticNormalizer.new(entry).normalize

    # Falls back to super (images from enclosures/content), which returns []
    # for this fixture entry
    assert_equal [], post.attachment_urls
  end
end
