require "test_helper"

class Normalizer::BuniNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

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
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should attach the full-size comic image from the page" do
    stub_comic_page
    entry = feed_entry(0)

    post = Normalizer::BuniNormalizer.new(entry).normalize

    assert_equal ["https://www.bunicomic.com/wp-content/uploads/2026/06/2026-06-10-Buni.jpg"], post.attachment_urls
  end

  test "#normalize should use the image alt text as post content" do
    stub_comic_page
    entry = feed_entry(0)

    post = Normalizer::BuniNormalizer.new(entry).normalize

    assert_equal "To eat or not to eat that last slice - #{PAGE_URL}", post.content
  end

  test "#normalize should reject the post when the comic page is unavailable" do
    stub_request(:get, PAGE_URL).to_return(status: 404)
    entry = feed_entry(0)

    post = Normalizer::BuniNormalizer.new(entry).normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "missing_images"
  end

  test "#normalize should warn when the comic page returns a non-2xx status" do
    stub_request(:get, PAGE_URL).to_return(status: 503)
    entry = feed_entry(0)
    warned = []
    Rails.logger.stub(:warn, ->(msg) { warned << msg }) do
      Normalizer::BuniNormalizer.new(entry).normalize
    end

    assert warned.any? { |msg| msg.include?("buni") && msg.include?("503") }, \
      "expected a logger.warn mentioning buni and HTTP 503"
  end

  test "#normalize should reject the post when the comic page fetch raises a network error" do
    stub_request(:get, PAGE_URL).to_raise(Faraday::ConnectionFailed.new("connection refused"))
    entry = feed_entry(0)

    post = Normalizer::BuniNormalizer.new(entry).normalize

    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "missing_images"
  end

  test "#normalize should warn when the comic page fetch raises a network error" do
    stub_request(:get, PAGE_URL).to_raise(Faraday::ConnectionFailed.new("connection refused"))
    entry = feed_entry(0)
    warned = []
    Rails.logger.stub(:warn, ->(msg) { warned << msg }) do
      Normalizer::BuniNormalizer.new(entry).normalize
    end

    assert warned.any? { |msg| msg.include?("buni") && msg.include?("network error") }, \
      "expected a logger.warn mentioning buni and network error"
  end

  test "#normalize should report to Rails.error when page fetched OK but comic image is absent" do
    stub_request(:get, PAGE_URL).to_return(status: 200, body: "<html><body><div id='comic'></div></body></html>")
    entry = feed_entry(0)
    reported = []
    Rails.error.stub(:report, ->(err, **) { reported << err }) do
      Normalizer::BuniNormalizer.new(entry).normalize
    end

    assert reported.any? { |err| err.message.include?("buni") && err.message.include?("markup changed") }, \
      "expected Rails.error.report to flag missing comic image as a structural bug"
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

    post = Normalizer::BuniNormalizer.new(entry).normalize

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

    post = Normalizer::BuniNormalizer.new(entry).normalize

    assert_empty post.comments
  end
end
