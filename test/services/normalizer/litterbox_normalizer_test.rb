require "test_helper"

class Normalizer::LitterboxNormalizerTest < ActiveSupport::TestCase
  include FixtureFeedEntries

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
    post = normalizer.normalize

    assert_matches_snapshot(post.normalized_attributes, snapshot: "#{fixture_dir}/normalized.json")
  end

  test "#normalize should use the entry title as content" do
    entry = feed_entry(0)

    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_equal "Sample Comic One - https://litterbox.example/sample-comic-one/", post.content
  end

  test "#normalize should include the bonus panel as a comment" do
    entry = feed_entry(0)

    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_equal ["Bonus panel: https://litterbox.example/wp-content/uploads/sample-comic-one-bonus.png"], post.comments
  end

  test "#normalize should fall back to content HTML image when page has no swiper" do
    entry = feed_entry(0)

    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_includes post.attachment_urls, "https://litterbox.example/wp-content/uploads/sample-comic-one.png"
  end

  test "#normalize should use swiper images when page has swiper-wrapper" do
    stub_request(:get, "https://litterbox.example/sample-comic-one/")
      .to_return(status: 200, body: file_fixture("feeds/litterbox/page_swiper.html").read)

    entry = feed_entry(0)
    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_equal [
      "https://litterbox.example/wp-content/uploads/sample-comic-one-1.png",
      "https://litterbox.example/wp-content/uploads/sample-comic-one-2.png"
    ], post.attachment_urls
  end

  test "#normalize should handle bonus page fetch failure gracefully" do
    stub_request(:get, "https://litterbox.example/sample-comic-one-bonus/")
      .to_raise(HttpClient::Error)

    entry = feed_entry(0)
    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_equal [], post.comments
  end

  test "#normalize should keep all four images in the sample gallery" do
    entry = sample_entries.find { |item| item.raw_data["title"] == "Sample Gallery" }
    stub_request(:get, entry.raw_data["link"]).to_return(body: "<article></article>")
    stub_request(:get, "https://litterbox.example/sample-gallery-bonus/").to_return(status: 404)

    post = Normalizer::LitterboxNormalizer.new(entry).normalize

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

    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_equal ["Bonus panel: https://www.patreon.com/litterboxcomics/posts/sample-bonus-123456"], post.comments
    assert_equal 1, post.attachment_urls.size
  end

  test "#normalize should omit generic Patreon bonus links in sample posts" do
    ["Sample Comic 5", "Sample Comic 8"].each do |title|
      entry = sample_entries.find { |item| item.raw_data["title"] == title }
      url = entry.raw_data.fetch("link")
      stub_request(:get, url).to_return(body: "<article></article>")
      stub_request(:get, "#{url.chomp('/')}-bonus/").to_return(status: 404)

      post = Normalizer::LitterboxNormalizer.new(entry).normalize

      assert_empty post.comments, title
      assert_equal 1, post.attachment_urls.size, title
      assert post.enqueued?, title
    end
  end

  test "#normalize should skip generic Patreon links and find a specific bonus post" do
    stub_request(:get, "https://litterbox.example/sample-comic-one-bonus/").to_return(status: 404)
    entry = feed_entry(0)
    bonus_url = "https://www.patreon.com/posts/sample-bonus-123456?utm_source=rss"
    entry.raw_data["content"] = <<~HTML
      <a href="https://www.patreon.com/sample-creator">Bonus panel</a>
      <a href="#{bonus_url}">Bonus panel</a>
    HTML

    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_equal ["Bonus panel: #{bonus_url}"], post.comments
  end

  test "#normalize should omit Patreon home and listing pages regardless of URL suffix" do
    stub_request(:get, "https://litterbox.example/sample-comic-one-bonus/").to_return(status: 404)

    %w[
      https://www.patreon.com/
      https://patreon.com/sample-creator/?utm_source=rss#bonus
      https://www.patreon.com/sample-creator/posts
      https://www.patreon.com/posts/
    ].each do |url|
      entry = feed_entry(0)
      entry.raw_data["content"] = %(<a href="#{url}">Bonus panel</a>)

      post = Normalizer::LitterboxNormalizer.new(entry).normalize

      assert_empty post.comments, url
    end
  end

  test "#normalize should reject standalone bonus posts without fetching another bonus" do
    ["https://litterbox.example/sample-bonus/", "https://litterbox.example/sample-bonus?ref=rss"].each do |url|
      entry = build(:feed_entry, feed: feed, raw_data: { "link" => url, "title" => "Sample Bonus" })

      post = Normalizer::LitterboxNormalizer.new(entry).normalize

      assert post.rejected?
      assert_includes post.validation_errors, "bonus"
      assert_empty post.comments
    end

    assert_not_requested :get, /sample-bonus/
  end

  test "#normalize should preserve every RSS image if the article fetch fails" do
    entry = sample_entries.find { |item| item.raw_data["title"] == "Sample Gallery" }
    stub_request(:get, entry.raw_data["link"]).to_raise(HttpClient::Error)
    stub_request(:get, "https://litterbox.example/sample-gallery-bonus/").to_return(status: 404)

    post = Normalizer::LitterboxNormalizer.new(entry).normalize

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

    post = Normalizer::LitterboxNormalizer.new(entry).normalize

    assert_equal expected.fetch("attachments"), post.attachment_urls
    assert_equal expected.fetch("comments"), post.comments
  end
end
