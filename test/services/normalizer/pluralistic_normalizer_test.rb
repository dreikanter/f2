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

  test "#normalize should warn when page fetch returns non-success status" do
    stub_request(:get, "https://pluralistic.net/2026/06/11/lapsarianism/")
      .to_return(status: 503, body: "")

    entry = feed_entry(0)

    log = capture_log { Normalizer::PluralisticNormalizer.new(entry).normalize }

    assert_match(/pluralistic: page fetch failed \(HTTP 503\)/, log)
  end

  test "#normalize should warn when page fetch raises a network error" do
    stub_request(:get, "https://pluralistic.net/2026/06/11/lapsarianism/")
      .to_raise(HttpClient::ConnectionError.new("connection refused"))

    entry = feed_entry(0)

    log = capture_log { Normalizer::PluralisticNormalizer.new(entry).normalize }

    assert_match(/pluralistic: page fetch error.*connection refused/, log)
  end

  test "#normalize should report error when page is fetched successfully but has no image" do
    stub_request(:get, "https://pluralistic.net/2026/06/11/lapsarianism/")
      .to_return(status: 200, body: "<html><body><article>No images here</article></body></html>")

    entry = feed_entry(0)
    reported = []

    Rails.error.stub(:report, ->(err, **) { reported << err.message }) do
      Normalizer::PluralisticNormalizer.new(entry).normalize
    end

    assert reported.any? { |msg| msg.match?(/no <img> found — markup changed/) },
           "expected Rails.error.report to be called when page has no images"
  end
end
