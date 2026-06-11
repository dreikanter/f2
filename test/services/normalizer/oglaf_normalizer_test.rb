require "test_helper"

class Normalizer::OglafNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

  def fixture_dir
    "feeds/oglaf"
  end

  def processor_class
    Processor::RssProcessor
  end

  def stub_story_pages
    stub_request(:get, "https://www.oglaf.com/sample/")
      .to_return(status: 200, body: file_fixture("#{fixture_dir}/page.html").read)
    stub_request(:get, "https://www.oglaf.com/sample/2/")
      .to_return(status: 200, body: file_fixture("#{fixture_dir}/page2.html").read)
  end

  test "#normalize should match the expected normalization result" do
    stub_story_pages
    entry = feed_entry(0)

    normalizer = Normalizer::OglafNormalizer.new(entry)
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should collect strip images and titles from every story page" do
    stub_story_pages
    entry = feed_entry(0)

    post = Normalizer::OglafNormalizer.new(entry).normalize

    assert_equal ["https://media.oglaf.com/comic/sample1.jpg", "https://media.oglaf.com/comic/sample2.jpg"], post.attachment_urls
    assert_equal ["Sample image title", "Another sample image title"], post.comments
  end

  test "#normalize should keep collected pages when a page fetch fails" do
    stub_request(:get, "https://www.oglaf.com/sample/")
      .to_return(status: 200, body: file_fixture("#{fixture_dir}/page.html").read)
    stub_request(:get, "https://www.oglaf.com/sample/2/").to_return(status: 500)
    entry = feed_entry(0)

    post = Normalizer::OglafNormalizer.new(entry).normalize

    assert_equal ["https://media.oglaf.com/comic/sample1.jpg"], post.attachment_urls
    assert_equal ["Sample image title"], post.comments
  end

  test "#normalize should return no attachments when the first page fetch raises a network error" do
    stub_request(:get, "https://www.oglaf.com/sample/")
      .to_raise(Faraday::ConnectionFailed.new("connection refused"))
    entry = feed_entry(0)

    post = Normalizer::OglafNormalizer.new(entry).normalize

    assert_empty post.attachment_urls
    assert_equal "enqueued", post.status
  end

  test "#normalize should stop following pages when the next-page URL is malformed" do
    stub_request(:get, "https://www.oglaf.com/sample/")
      .to_return(status: 200, body: <<~HTML)
        <html>
        <head><link rel="next" href="/sample story/2/" /></head>
        <body><img id="strip" src="https://media.oglaf.com/comic/sample1.jpg" title="Alt text" /></body>
        </html>
      HTML
    entry = feed_entry(0)

    post = Normalizer::OglafNormalizer.new(entry).normalize

    assert_equal ["https://media.oglaf.com/comic/sample1.jpg"], post.attachment_urls
    assert_equal "enqueued", post.status
  end

  test "#normalize should not follow a next link that points at another story" do
    stub_request(:get, "https://www.oglaf.com/another/").to_return(status: 200, body: <<~HTML)
      <html>
      <head><link rel="next" href="/unrelated/" /></head>
      <body><img id="strip" src="https://media.oglaf.com/comic/another.jpg" title="Another strip title" /></body>
      </html>
    HTML
    entry = feed_entry(1)

    post = Normalizer::OglafNormalizer.new(entry).normalize

    assert_equal ["https://media.oglaf.com/comic/another.jpg"], post.attachment_urls
    assert_equal "enqueued", post.status
  end

  test "#normalize should report via Rails.error when img#strip is absent on a fetched page" do
    stub_request(:get, "https://www.oglaf.com/sample/")
      .to_return(status: 200, body: "<html><body><p>No strip here</p></body></html>")
    entry = feed_entry(0)
    reported = []

    Rails.error.stub(:report, ->(err, **kwargs) { reported << [err.message, kwargs] }) do
      post = Normalizer::OglafNormalizer.new(entry).normalize
      assert_empty post.attachment_urls
    end

    assert_equal 1, reported.size
    assert_match(/img#strip missing/, reported.first[0])
    assert_equal entry.feed&.id, reported.first[1].dig(:context, :feed_id)
    assert_equal entry.uid, reported.first[1].dig(:context, :entry_uid)
  end
end
