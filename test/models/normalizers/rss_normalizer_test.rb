require "test_helper"

class Normalizers::RssNormalizerTest < ActiveSupport::TestCase
  test "should inherit from base normalizer" do
    feed = create(:feed, normalizer: "rss")
    normalizer = Normalizers::RssNormalizer.new(feed, [])
    assert_kind_of Normalizers::Base, normalizer
  end

  test "should initialize without errors" do
    feed = create(:feed, normalizer: "rss")
    items = ["item1", "item2"]
    assert_nothing_raised do
      Normalizers::RssNormalizer.new(feed, items)
    end
  end

  test "should respond to normalize method" do
    feed = create(:feed, normalizer: "rss")
    normalizer = Normalizers::RssNormalizer.new(feed, [])
    assert_respond_to normalizer, :normalize
  end

  test "should normalize processed items" do
    feed = create(:feed, normalizer: "rss")
    items = [
      { title: "<h1>Test Article</h1>", content: "<p>Test content</p>", published_at: Time.current, url: "https://example.com" }
    ]
    normalizer = Normalizers::RssNormalizer.new(feed, items)
    
    result = normalizer.normalize
    
    assert_equal 1, result.length
    assert_equal feed.id, result[0][:feed_id]
    assert_equal "Test Article", result[0][:title]
    assert_equal "Test content", result[0][:content]
    assert_equal "https://example.com", result[0][:source_url]
  end

  test "should handle blank text in clean_html" do
    feed = create(:feed, normalizer: "rss")
    items = [
      { title: nil, content: "", published_at: Time.current, url: "https://example.com" }
    ]
    normalizer = Normalizers::RssNormalizer.new(feed, items)
    
    result = normalizer.normalize
    
    assert_nil result[0][:title]
    assert_equal "", result[0][:content]
  end
end
