require "test_helper"

class Normalizer::SmbcNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries
  include DnsTestHelper

  def fixture_dir
    "feeds/smbc"
  end

  def processor_class
    Processor::RssProcessor
  end

  def stub_comic_page
    stub_request(:get, "https://www.smbc-comics.com/comic/sample-comic-one")
      .to_return(status: 200, body: file_fixture("feeds/smbc/page.html").read)
  end

  test "#normalize should match the expected normalization result" do
    stub_comic_page
    entry = feed_entry(0)

    normalizer = Normalizer::SmbcNormalizer.new(entry)
    post = stub_dns { normalizer.normalize }

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should skip the hidden panel when the page fetch fails" do
    stub_request(:get, "https://www.smbc-comics.com/comic/sample-comic-one").to_return(status: 404)
    entry = feed_entry(0)

    post = stub_dns { Normalizer::SmbcNormalizer.new(entry).normalize }

    assert_equal ["https://www.smbc-comics.com/comics/sample-comic-one.png"], post.attachment_urls
    assert_equal ["Sample hovertext for the first comic."], post.comments
    assert_equal "enqueued", post.status
  end

  test "#normalize should skip the hidden panel when the page fetch raises a network error" do
    stub_request(:get, "https://www.smbc-comics.com/comic/sample-comic-one")
      .to_raise(Faraday::ConnectionFailed.new("connection refused"))
    entry = feed_entry(0)

    post = stub_dns { Normalizer::SmbcNormalizer.new(entry).normalize }

    assert_equal ["https://www.smbc-comics.com/comics/sample-comic-one.png"], post.attachment_urls
    assert_equal ["Sample hovertext for the first comic."], post.comments
    assert_equal "enqueued", post.status
  end
end
