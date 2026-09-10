require "test_helper"

class Normalizer::XkcdNormalizerTest < ActiveSupport::TestCase
  include DnsTestHelper
  include FixtureFeedEntries

  def fixture_dir
    "feeds/xkcd"
  end

  def processor_class
    Processor::RssProcessor
  end

  test "#normalize should match the expected normalization result" do
    entry = feed_entry(0)
    stub_request(:get, entry.raw_data.fetch("link")).to_return(status: 503)

    normalizer = Normalizer::XkcdNormalizer.new(entry)
    post = stub_dns { normalizer.normalize }

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should use the advertised full-resolution image and retain feed hovertext" do
    entry = build(:feed_entry, raw_data: {
      "title" => "Sample comic",
      "link" => "https://example.com/comic",
      "summary" => '<img src="https://images.example.com/small.png" title="Sample hovertext">'
    })
    stub_request(:get, "https://example.com/comic")
      .to_return(body: '<meta property="og:image" content="https://images.example.com/large.png">')

    post = stub_dns { Normalizer::XkcdNormalizer.new(entry).normalize }

    assert_equal ["https://images.example.com/large.png"], post.attachment_urls
    assert_equal ["Sample hovertext"], post.comments
  end

  test "#normalize should keep the feed image when the page advertises an unsafe image" do
    entry = build(:feed_entry, raw_data: {
      "link" => "https://example.com/comic",
      "summary" => '<img src="https://images.example.com/small.png">'
    })
    stub_request(:get, "https://example.com/comic").to_return(body: '<meta property="og:image" content="file:///etc/passwd">')

    post = stub_dns { Normalizer::XkcdNormalizer.new(entry).normalize }

    assert_equal ["https://images.example.com/small.png"], post.attachment_urls
  end

  test "#normalize should keep the feed image without fetching a private page URL" do
    entry = build(:feed_entry, raw_data: {
      "link" => "http://169.254.169.254/latest/meta-data/",
      "summary" => '<img src="https://images.example.com/small.png">'
    })

    post = Normalizer::XkcdNormalizer.new(entry).normalize

    assert_equal ["https://images.example.com/small.png"], post.attachment_urls
    assert_not_requested :get, /./
  end
end
