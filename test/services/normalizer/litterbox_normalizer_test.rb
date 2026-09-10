require "test_helper"

class Normalizer::LitterboxNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries
  include DnsTestHelper

  def fixture_dir
    "feeds/litterbox"
  end

  def processor_class
    Processor::RssProcessor
  end

  setup do
    stub_request(:get, "https://litterbox.example/sample-comic-one/")
      .to_return(status: 200, body: file_fixture("feeds/litterbox/page.html").read)
    stub_request(:get, "https://litterbox.example/sample-comic-one-bonus/")
      .to_return(status: 200, body: file_fixture("feeds/litterbox/bonus_page.html").read)
  end

  test "#normalize should match the expected normalization result" do
    entry = feed_entry(0)

    normalizer = Normalizer::LitterboxNormalizer.new(entry)
    post = stub_dns { normalizer.normalize }

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should use swiper images when page has swiper-wrapper" do
    stub_request(:get, "https://litterbox.example/sample-comic-one/")
      .to_return(status: 200, body: file_fixture("feeds/litterbox/page_swiper.html").read)

    entry = feed_entry(0)
    post = stub_dns { Normalizer::LitterboxNormalizer.new(entry).normalize }

    assert_equal [
      "https://litterbox.example/wp-content/uploads/sample-comic-one-1.png",
      "https://litterbox.example/wp-content/uploads/sample-comic-one-2.png"
    ], post.attachment_urls
  end

  test "#normalize should handle bonus page fetch failure gracefully" do
    stub_request(:get, "https://litterbox.example/sample-comic-one-bonus/")
      .to_raise(HttpClient::Error)

    entry = feed_entry(0)
    post = stub_dns { Normalizer::LitterboxNormalizer.new(entry).normalize }

    assert_equal [], post.comments
  end

  test "#normalize should keep all four images in the sample gallery" do
    entry = sample_entries.find { |item| item.raw_data["title"] == "Sample Gallery" }
    stub_request(:get, entry.raw_data["link"]).to_return(body: "<article></article>")
    stub_request(:get, "https://litterbox.example/sample-gallery-bonus/").to_return(status: 404)

    post = stub_dns { Normalizer::LitterboxNormalizer.new(entry).normalize }

    assert_equal %w[
      sample-gallery-panel-1.png
      sample-gallery-panel-2.png
      sample-gallery-panel-3.png
      sample-gallery-panel-4.png
    ], post.attachment_urls.map { |url| File.basename(URI.parse(url).path) }
    assert post.enqueued?
  end

  test "#normalize should retain a sample Patreon bonus link when the public bonus page is absent" do
    entry = sample_entries.find { |item| item.raw_data["title"] == "Sample Comic 3" }
    stub_request(:get, entry.raw_data["link"]).to_return(body: "<article></article>")
    stub_request(:get, "https://litterbox.example/sample-comic-3-bonus/").to_return(status: 404)

    post = stub_dns { Normalizer::LitterboxNormalizer.new(entry).normalize }

    assert_equal ["Bonus panel: https://www.patreon.com/litterboxcomics/posts/sample-bonus-123456"], post.comments
    assert_equal 1, post.attachment_urls.size
  end

  test "#normalize should omit the generic Patreon bonus link in Sample Comic 5" do
    entry = sample_entries.find { |item| item.raw_data["title"] == "Sample Comic 5" }
    url = entry.raw_data.fetch("link")
    stub_request(:get, url).to_return(body: "<article></article>")
    stub_request(:get, "#{url.chomp('/')}-bonus/").to_return(status: 404)

    post = stub_dns { Normalizer::LitterboxNormalizer.new(entry).normalize }

    assert_empty post.comments
    assert_equal 1, post.attachment_urls.size
    assert post.enqueued?
  end

  test "#normalize should omit the generic Patreon bonus link in Sample Comic 8" do
    entry = sample_entries.find { |item| item.raw_data["title"] == "Sample Comic 8" }
    url = entry.raw_data.fetch("link")
    stub_request(:get, url).to_return(body: "<article></article>")
    stub_request(:get, "#{url.chomp('/')}-bonus/").to_return(status: 404)

    post = stub_dns { Normalizer::LitterboxNormalizer.new(entry).normalize }

    assert_empty post.comments
    assert_equal 1, post.attachment_urls.size
    assert post.enqueued?
  end

  test "#normalize should skip generic Patreon links and find a specific bonus post" do
    stub_request(:get, "https://litterbox.example/sample-comic-one-bonus/").to_return(status: 404)
    entry = feed_entry(0)
    bonus_url = "https://www.patreon.com/posts/sample-bonus-123456?utm_source=rss"
    entry.raw_data["content"] = <<~HTML
      <a href="https://www.patreon.com/sample-creator">Bonus panel</a>
      <a href="#{bonus_url}">Bonus panel</a>
    HTML

    post = stub_dns { Normalizer::LitterboxNormalizer.new(entry).normalize }

    assert_equal ["Bonus panel: #{bonus_url}"], post.comments
  end

  test "#normalize should omit Patreon home as a bonus link" do
    stub_request(:get, "https://litterbox.example/sample-comic-one-bonus/").to_return(status: 404)
    entry = feed_entry(0)
    entry.raw_data["content"] = '<a href="https://www.patreon.com/">Bonus panel</a>'

    post = stub_dns { Normalizer::LitterboxNormalizer.new(entry).normalize }

    assert_empty post.comments
  end

  test "#normalize should omit a Patreon profile with tracking parameters as a bonus link" do
    stub_request(:get, "https://litterbox.example/sample-comic-one-bonus/").to_return(status: 404)
    entry = feed_entry(0)
    entry.raw_data["content"] = '<a href="https://patreon.com/sample-creator/?utm_source=rss#bonus">Bonus panel</a>'

    post = stub_dns { Normalizer::LitterboxNormalizer.new(entry).normalize }

    assert_empty post.comments
  end

  test "#normalize should omit a creator post listing as a bonus link" do
    stub_request(:get, "https://litterbox.example/sample-comic-one-bonus/").to_return(status: 404)
    entry = feed_entry(0)
    entry.raw_data["content"] = '<a href="https://www.patreon.com/sample-creator/posts">Bonus panel</a>'

    post = stub_dns { Normalizer::LitterboxNormalizer.new(entry).normalize }

    assert_empty post.comments
  end

  test "#normalize should omit the Patreon post listing as a bonus link" do
    stub_request(:get, "https://litterbox.example/sample-comic-one-bonus/").to_return(status: 404)
    entry = feed_entry(0)
    entry.raw_data["content"] = '<a href="https://www.patreon.com/posts/">Bonus panel</a>'

    post = stub_dns { Normalizer::LitterboxNormalizer.new(entry).normalize }

    assert_empty post.comments
  end

  test "#normalize should reject standalone bonus posts without fetching another bonus" do
    entry = build(:feed_entry, feed: feed, raw_data: { "link" => "https://litterbox.example/sample-bonus/", "title" => "Sample Bonus" })

    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert post.rejected?
    assert_includes post.validation_errors, "bonus"
    assert_empty post.comments
    assert_not_requested :get, /sample-bonus/
  end

  test "#normalize should reject bonus posts with query parameters without fetching another bonus" do
    entry = build(:feed_entry, feed: feed, raw_data: { "link" => "https://litterbox.example/sample-bonus?ref=rss", "title" => "Sample Bonus" })

    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert post.rejected?
    assert_includes post.validation_errors, "bonus"
    assert_empty post.comments
    assert_not_requested :get, /sample-bonus/
  end

  test "#normalize should preserve every RSS image if the article fetch fails" do
    entry = sample_entries.find { |item| item.raw_data["title"] == "Sample Gallery" }
    stub_request(:get, entry.raw_data["link"]).to_raise(HttpClient::Error)
    stub_request(:get, "https://litterbox.example/sample-gallery-bonus/").to_return(status: 404)

    post = stub_dns { Normalizer::LitterboxNormalizer.new(entry).normalize }

    assert_equal 4, post.attachment_urls.size
    assert post.enqueued?
  end

  def sample_entries
    Processor::RssProcessor.new(feed, file_fixture("#{fixture_dir}/current.xml").read).process.entries
  end

  test "#normalize should preserve all eight carousel panels and the bonus from the sample carousel" do
    entry = Processor::RssProcessor.new(feed, file_fixture("#{fixture_dir}/legacy_slides.xml").read).process.entries.first
    expected = JSON.parse(file_fixture("#{fixture_dir}/legacy_slides.json").read)
    stub_request(:get, "https://litterbox.example/sample-carousel/")
      .to_return(body: file_fixture("#{fixture_dir}/legacy_slides.html").read)
    stub_request(:get, "https://litterbox.example/sample-carousel-bonus/")
      .to_return(body: '<meta property="og:image" content="https://litterbox.example/wp-content/uploads/sample-carousel-bonus.png">')

    post = stub_dns { Normalizer::LitterboxNormalizer.new(entry).normalize }

    assert_equal expected.fetch("attachments"), post.attachment_urls
    assert_equal expected.fetch("comments"), post.comments
  end
end
