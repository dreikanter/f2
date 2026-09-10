require "test_helper"

class Normalizer::PluralisticNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries
  include DnsTestHelper

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
    post = stub_dns { normalizer.normalize }

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should fall back to inherited defaults when page fetch fails" do
    stub_request(:get, "https://pluralistic.net/2026/06/11/lapsarianism/")
      .to_return(status: 503, body: "")

    entry = feed_entry(0)

    post = stub_dns { Normalizer::PluralisticNormalizer.new(entry).normalize }

    # Falls back to super (images from enclosures/content), which returns []
    # for this fixture entry
    assert_equal [], post.attachment_urls
  end

  test "#normalize should omit the cover image on network error" do
    stub_request(:get, "https://pluralistic.net/2026/06/11/lapsarianism/")
      .to_raise(HttpClient::ConnectionError.new("connection refused"))
    entry = feed_entry(0)

    post = stub_dns { Normalizer::PluralisticNormalizer.new(entry).normalize }

    assert_empty post.attachment_urls
  end

  test "#normalize should report error when page is fetched successfully but has no image" do
    stub_request(:get, "https://pluralistic.net/2026/06/11/lapsarianism/")
      .to_return(status: 200, body: "<html><body><article>No images here</article></body></html>")

    entry = feed_entry(0)
    reported = []

    Rails.error.stub(:report, ->(err, **) { reported << err.message }) do
      stub_dns { Normalizer::PluralisticNormalizer.new(entry).normalize }
    end

    assert reported.any? { |msg| msg.match?(/no <img> found — markup changed/) },
           "expected Rails.error.report to be called when page has no images"
  end
end
