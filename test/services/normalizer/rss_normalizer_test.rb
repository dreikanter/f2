require "test_helper"

class Normalizer::RssNormalizerTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed)
  end

  def processor
    Processor::RssProcessor.new(feed, file_fixture("sample_rss.xml").read)
  end

  def feed_entries
    @feed_entries ||= processor.process
  end

  def feed_entry(index)
    entry = feed_entries[index]
    entry.save!
    entry
  end

  test "should create valid post from feed entry" do
    entry = feed_entry(0)

    normalizer = Normalizer::RssNormalizer.new(entry)
    post = normalizer.normalize

    assert_instance_of Post, post
    assert_equal entry.feed, post.feed
    assert_equal entry, post.feed_entry
    assert_equal entry.uid, post.uid
    assert_equal entry.published_at, post.published_at
    assert_equal "https://example.com/first-article", post.source_url
    assert_equal "This is the first article content with some HTML tags.", post.content
    assert_equal [], post.attachment_urls
    assert_equal [], post.comments
    assert_equal "enqueued", post.status
    assert_equal [], post.validation_errors
  end

  test "should extract content from title when description is missing" do
    entry = feed_entry(2)

    normalizer = Normalizer::RssNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal "Article Without Content", post.content
  end

  test "should reject post with blank content and no images" do
    entry = create(:feed_entry, raw_data: {
      "title" => "",
      "content" => "",
      "summary" => "",
      "link" => "https://example.com/blank"
    })

    normalizer = Normalizer::RssNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal "", post.content
    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "no_content_or_images"
  end

  test "should normalize future publication date to current date" do
    future_time = 1.hour.from_now
    entry = create(:feed_entry, published_at: future_time)

    normalizer = Normalizer::RssNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal "enqueued", post.status
    assert_equal [], post.validation_errors
    assert_equal Time.current.to_date, post.published_at.to_date
    assert post.published_at <= Time.current
  end

  test "should truncate content that is too long" do
    long_content = "a" * (Post::MAX_CONTENT_LENGTH + 100)
    entry = create(:feed_entry, raw_data: {
      "summary" => long_content,
      "link" => "https://example.com/long"
    })

    normalizer = Normalizer::RssNormalizer.new(entry)
    post = normalizer.normalize

    assert_equal "enqueued", post.status
    assert_equal [], post.validation_errors
    assert post.content.length <= Post::MAX_CONTENT_LENGTH
    assert post.content.ends_with?("...")
  end
end
