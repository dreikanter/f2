require "test_helper"

class Normalizer::BuniNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries
  include DnsTestHelper

  PAGE_URL = "https://www.bunicomic.com/comic/buni-1983/".freeze

  def fixture_dir
    "feeds/buni"
  end

  def processor_class
    Processor::RssProcessor
  end

  def stub_comic_page
    stub_request(:get, PAGE_URL)
      .to_return(status: 200, body: file_fixture("#{fixture_dir}/page.html").read)
  end

  test "#normalize should match the expected normalization result" do
    stub_comic_page
    entry = feed_entry(0)

    normalizer = Normalizer::BuniNormalizer.new(entry)
    post = stub_dns { normalizer.normalize }

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should reject the post when the comic page is unavailable" do
    stub_request(:get, PAGE_URL).to_return(status: 404)
    entry = feed_entry(0)

    post = stub_dns { Normalizer::BuniNormalizer.new(entry).normalize }

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "missing_images"
    assert_requested :get, PAGE_URL, times: 1
  end

  test "#normalize should report a network error once with entry context" do
    stub_request(:get, PAGE_URL).to_raise(Faraday::ConnectionFailed.new("connection refused"))
    entry = feed_entry(0)
    reported = []
    Rails.error.stub(:report, ->(error, **options) { reported << [error, options] }) do
      post = stub_dns { Normalizer::BuniNormalizer.new(entry).normalize }
      assert_equal "rejected", post.status
      assert_includes post.validation_errors, "missing_images"
    end

    assert_equal 1, reported.size
    _, options = reported.first
    assert_equal({ normalizer: "Normalizer::BuniNormalizer", feed_id: entry.feed.id,
                   uid: entry.uid, url: PAGE_URL }, options[:context])
    assert_requested :get, PAGE_URL, times: 1
  end

  test "#normalize should report a missing comic image when the successful response is empty" do
    stub_request(:get, PAGE_URL).to_return(status: 200, body: "")
    entry = feed_entry(0)
    reported = []

    Rails.error.stub(:report, ->(error, **) { reported << error }) do
      post = stub_dns { Normalizer::BuniNormalizer.new(entry).normalize }
      assert_includes post.validation_errors, "missing_images"
    end

    assert_equal 1, reported.size
    assert_match(/comic image missing/, reported.first.message)
  end

  test "#normalize should report a missing comic image when the page has no comic" do
    stub_request(:get, PAGE_URL).to_return(status: 200, body: "<html><body><div id='comic'></div></body></html>")
    entry = feed_entry(0)
    reported = []

    Rails.error.stub(:report, ->(error, **) { reported << error }) do
      post = stub_dns { Normalizer::BuniNormalizer.new(entry).normalize }
      assert_includes post.validation_errors, "missing_images"
    end

    assert_equal 1, reported.size
    assert_match(/comic image missing/, reported.first.message)
  end

  test "#normalize should add a Webtoons comment when the entry links to Webtoons" do
    webtoons_url = "https://www.webtoons.com/en/comedy/buni/ep-1/viewer"
    entry = FeedEntry.new(
      feed: feed,
      uid: "https://www.bunicomic.com/comic/buni-webtoons/",
      published_at: 1.hour.ago,
      status: :pending,
      raw_data: {
        "title" => "Buni on Webtoons",
        "link" => webtoons_url,
        "url" => webtoons_url,
        "content" => %(<a href="#{webtoons_url}">Read on Webtoons</a>),
        "published" => 1.hour.ago.rfc3339
      }
    )
    entry.save!
    stub_request(:get, webtoons_url)
      .to_return(status: 200, body: '<html><body><div class="entry"><img srcset="https://cdn.webtoons.com/img.jpg 1x" src="https://cdn.webtoons.com/img.jpg" /></div></body></html>')

    post = stub_dns { Normalizer::BuniNormalizer.new(entry).normalize }

    assert_includes post.comments, "Check out today's comic on Webtoons: #{webtoons_url}"
    assert_equal ["https://cdn.webtoons.com/img.jpg"], post.attachment_urls
  end

  test "#normalize should treat a malformed link href as non-Webtoons" do
    entry = FeedEntry.new(
      feed: feed,
      uid: "https://www.bunicomic.com/comic/buni-baduri/",
      published_at: 1.hour.ago,
      status: :pending,
      raw_data: {
        "title" => "Buni",
        "link" => PAGE_URL,
        "url" => PAGE_URL,
        "content" => '<a href="https://тест.example.com/buni">bad link</a>',
        "published" => 1.hour.ago.rfc3339
      }
    )
    entry.save!
    stub_request(:get, PAGE_URL)
      .to_return(status: 200, body: file_fixture("#{fixture_dir}/page.html").read)

    post = stub_dns { Normalizer::BuniNormalizer.new(entry).normalize }

    assert_empty post.comments
  end
end
