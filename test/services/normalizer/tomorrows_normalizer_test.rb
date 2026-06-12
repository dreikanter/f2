require "test_helper"

class Normalizer::TomorrowsNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/tomorrows"
  end

  def processor_class
    Processor::RssProcessor
  end

  setup do
    stub_request(:get, "https://365tomorrows.com/2026/06/10/the-black-cube/")
      .to_return(status: 200, body: file_fixture("feeds/tomorrows/page.html").read)
  end

  test "#normalize should match the expected normalization result" do
    entry = feed_entry(0)

    normalizer = Normalizer::TomorrowsNormalizer.new(entry)
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should use the entry title as content" do
    entry = feed_entry(0)

    post = Normalizer::TomorrowsNormalizer.new(entry).normalize

    assert_equal "The Black Cube - https://365tomorrows.com/2026/06/10/the-black-cube/", post.content
  end

  test "#normalize should include story text as a comment" do
    entry = feed_entry(0)

    post = Normalizer::TomorrowsNormalizer.new(entry).normalize

    assert_equal 1, post.comments.size
    assert_includes post.comments.first, "There was a moment, in his dream"
  end

  test "#normalize should fall back to feed summary when page fetch fails" do
    stub_request(:get, "https://365tomorrows.com/2026/06/10/the-black-cube/")
      .to_return(status: 503)

    entry = feed_entry(0)
    post = Normalizer::TomorrowsNormalizer.new(entry).normalize

    assert_equal 1, post.comments.size
    assert_includes post.comments.first, "Author: Bill Cox"
  end

  test "#normalize should warn when page fetch fails and falling back to RSS summary" do
    stub_request(:get, "https://365tomorrows.com/2026/06/10/the-black-cube/")
      .to_return(status: 503)

    entry = feed_entry(0)
    warnings = []
    Rails.logger.stub(:warn, ->(msg) { warnings << msg }) do
      Normalizer::TomorrowsNormalizer.new(entry).normalize
    end

    assert warnings.any? { |w| w.include?("tomorrows") && w.include?("falling back") },
           "expected a warn log mentioning tomorrows and fallback"
  end

  test "#normalize should report via Rails.error when page fetched but .entry-content missing" do
    stub_request(:get, "https://365tomorrows.com/2026/06/10/the-black-cube/")
      .to_return(status: 200, body: "<html><body><p>no entry-content here</p></body></html>")

    entry = feed_entry(0)
    reported = []
    Rails.error.stub(:report, ->(err, **) { reported << err }) do
      Normalizer::TomorrowsNormalizer.new(entry).normalize
    end

    assert reported.any? { |e| e.message.include?(".entry-content missing") },
           "expected Rails.error.report for missing .entry-content"
  end

  test "#normalize should not report via Rails.error on transient page fetch failure" do
    stub_request(:get, "https://365tomorrows.com/2026/06/10/the-black-cube/")
      .to_return(status: 503)

    entry = feed_entry(0)
    reported = []
    Rails.error.stub(:report, ->(err, **) { reported << err }) do
      Normalizer::TomorrowsNormalizer.new(entry).normalize
    end

    assert_empty reported, "should not report transient HTTP failures to Rails.error"
  end
end
