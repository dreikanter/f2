require "test_helper"

class Normalizer::NextbigfutureNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/nextbigfuture"
  end

  def processor_class
    Processor::RssProcessor
  end

  setup do
    stub_request(:get, "https://example.com/2025/01/sample-article-one.html")
      .to_return(status: 200, body: file_fixture("feeds/nextbigfuture/page.html").read)
  end

  test "#normalize should match the expected normalization result" do
    entry = feed_entry(0)

    post = Normalizer::NextbigfutureNormalizer.new(entry).normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should extract the title as content" do
    entry = feed_entry(0)

    post = Normalizer::NextbigfutureNormalizer.new(entry).normalize

    assert_includes post.content, "Sample Article One"
  end

  test "#normalize should include stripped summary as a comment" do
    entry = feed_entry(0)

    post = Normalizer::NextbigfutureNormalizer.new(entry).normalize

    assert_equal 1, post.comments.size
    assert_includes post.comments.first, "introductory text about the topic"
  end

  test "#normalize should fetch the featured image from the article page" do
    entry = feed_entry(0)

    post = Normalizer::NextbigfutureNormalizer.new(entry).normalize

    assert_equal ["https://example.com/uploads/2025/01/sample-photo.jpg"],
                 post.attachment_urls
  end

  test "#normalize should return no attachments when page fetch fails" do
    stub_request(:get, "https://example.com/2025/01/sample-article-one.html")
      .to_return(status: 404)

    entry = feed_entry(0)

    post = Normalizer::NextbigfutureNormalizer.new(entry).normalize

    assert_equal [], post.attachment_urls
  end
end
