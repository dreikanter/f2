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
    stub_request(:get, "https://www.oglaf.com/goat/")
      .to_return(status: 200, body: file_fixture("#{fixture_dir}/page.html").read)
    stub_request(:get, "https://www.oglaf.com/goat/2/")
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

    assert_equal ["https://media.oglaf.com/comic/goat1.jpg", "https://media.oglaf.com/comic/goat2.jpg"], post.attachment_urls
    assert_equal ["Territorial disputes with the God of nipples", "My sacred drink is orange juice. Milk is more a work thing"], post.comments
  end

  test "#normalize should keep collected pages when a page fetch fails" do
    stub_request(:get, "https://www.oglaf.com/goat/")
      .to_return(status: 200, body: file_fixture("#{fixture_dir}/page.html").read)
    stub_request(:get, "https://www.oglaf.com/goat/2/").to_return(status: 500)
    entry = feed_entry(0)

    post = Normalizer::OglafNormalizer.new(entry).normalize

    assert_equal ["https://media.oglaf.com/comic/goat1.jpg"], post.attachment_urls
    assert_equal ["Territorial disputes with the God of nipples"], post.comments
  end

  test "#normalize should not follow a next link that points at another story" do
    stub_request(:get, "https://www.oglaf.com/lolth/").to_return(status: 200, body: <<~HTML)
      <html>
      <head><link rel="next" href="/accounting/" /></head>
      <body><img id="strip" src="https://media.oglaf.com/comic/lolth.jpg" title="two sets of demonweb arms, four demonweb pits" /></body>
      </html>
    HTML
    entry = feed_entry(1)

    post = Normalizer::OglafNormalizer.new(entry).normalize

    assert_equal ["https://media.oglaf.com/comic/lolth.jpg"], post.attachment_urls
    assert_equal "enqueued", post.status
  end
end
