require "test_helper"

class Normalizer::SmbcNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/smbc"
  end

  def processor_class
    Processor::RssProcessor
  end

  def stub_comic_page
    stub_request(:get, "https://www.smbc-comics.com/comic/huh-2")
      .to_return(status: 200, body: file_fixture("feeds/smbc/page.html").read)
  end

  test "#normalize should match the expected normalization result" do
    stub_comic_page
    entry = feed_entry(0)

    normalizer = Normalizer::SmbcNormalizer.new(entry)
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should strip the title prefix from content" do
    stub_comic_page
    entry = feed_entry(0)

    post = Normalizer::SmbcNormalizer.new(entry).normalize

    assert_equal "Huh - https://www.smbc-comics.com/comic/huh-2", post.content
  end

  test "#normalize should attach the comic and the hidden panel" do
    stub_comic_page
    entry = feed_entry(0)

    post = Normalizer::SmbcNormalizer.new(entry).normalize

    expected = [
      "https://www.smbc-comics.com/comics/1780969506-20260611.png",
      "https://www.smbc-comics.com/comics/178096959820260611after.png"
    ]
    assert_equal expected, post.attachment_urls
  end

  test "#normalize should add the hovertext as a comment" do
    stub_comic_page
    entry = feed_entry(0)

    post = Normalizer::SmbcNormalizer.new(entry).normalize

    assert_equal ["Once I realized this, all those inept AI laundry-folding videos became hilarious."], post.comments
  end

  test "#normalize should skip the hidden panel when the page fetch fails" do
    stub_request(:get, "https://www.smbc-comics.com/comic/huh-2").to_return(status: 404)
    entry = feed_entry(0)

    post = Normalizer::SmbcNormalizer.new(entry).normalize

    assert_equal ["https://www.smbc-comics.com/comics/1780969506-20260611.png"], post.attachment_urls
    assert_equal "enqueued", post.status
  end
end
