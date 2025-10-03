require "test_helper"

class Normalizer::XkcdNormalizerTest < ActiveSupport::TestCase
  def feed_entry_with_xkcd_data(raw_data = {})
    default_data = {
      "id" => "https://xkcd.com/3149/",
      "url" => "https://xkcd.com/3149/",
      "title" => "Measure Twice, Cut Once",
      "summary" => '<img src="https://imgs.xkcd.com/comics/measure_twice_cut_once.png" title="&quot;Measure zero times, cut zero times.&quot; --carpenter who has achieved enlightenment and realized the wood is fine where it is" alt="&quot;Measure zero times, cut zero times.&quot; --carpenter who has achieved enlightenment and realized the wood is fine where it is" />',
      "content" => "",
      "enclosures" => []
    }

    create(:feed_entry, raw_data: default_data.merge(raw_data))
  end

  test "extracts content from image title attributes" do
    feed_entry = feed_entry_with_xkcd_data

    normalizer = Normalizer::XkcdNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_equal '"Measure zero times, cut zero times." --carpenter who has achieved enlightenment and realized the wood is fine where it is', post.content
    assert_equal "enqueued", post.status
  end

  test "extracts attachment URLs from summary field" do
    feed_entry = feed_entry_with_xkcd_data

    normalizer = Normalizer::XkcdNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_includes post.attachment_urls, "https://imgs.xkcd.com/comics/measure_twice_cut_once.png"
    assert_equal 1, post.attachment_urls.size
  end

  test "handles different XKCD comic" do
    xkcd_data = {
      "id" => "https://xkcd.com/3148/",
      "url" => "https://xkcd.com/3148/",
      "title" => "100% All Achievements",
      "summary" => '<img src="https://imgs.xkcd.com/comics/100_all_achievements.png" title="I\'m trying to share my footage of the full run to prove it\'s not tool-assisted, but the uploader has problems with video lengths of more than a decade." alt="I\'m trying to share my footage of the full run to prove it\'s not tool-assisted, but the uploader has problems with video lengths of more than a decade." />'
    }

    feed_entry = feed_entry_with_xkcd_data(xkcd_data)

    normalizer = Normalizer::XkcdNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_equal "I'm trying to share my footage of the full run to prove it's not tool-assisted, but the uploader has problems with video lengths of more than a decade.", post.content
    assert_includes post.attachment_urls, "https://imgs.xkcd.com/comics/100_all_achievements.png"
  end

  test "extracts images from both summary and content fields" do
    mixed_data = {
      "summary" => '<img src="https://imgs.xkcd.com/comics/summary_image.png" title="Summary image" />',
      "content" => '<p>Content with <img src="https://imgs.xkcd.com/comics/content_image.png" /></p>'
    }

    feed_entry = feed_entry_with_xkcd_data(mixed_data)

    normalizer = Normalizer::XkcdNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_includes post.attachment_urls, "https://imgs.xkcd.com/comics/summary_image.png"
    assert_includes post.attachment_urls, "https://imgs.xkcd.com/comics/content_image.png"
    assert_equal 2, post.attachment_urls.size
  end

  test "falls back to regular RSS processing when no image titles found" do
    fallback_data = {
      "summary" => "<div>Some plain text content without images</div>",
      "content" => "",
      "title" => "Plain Text Entry"
    }

    feed_entry = feed_entry_with_xkcd_data(fallback_data)

    normalizer = Normalizer::XkcdNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_equal "Some plain text content without images", post.content
    assert_equal [], post.attachment_urls
  end

  test "handles images without title attributes" do
    no_title_data = {
      "summary" => '<img src="https://imgs.xkcd.com/comics/no_title.png" alt="Image without title" />',
      "content" => "",
      "title" => "Fallback to title"
    }

    feed_entry = feed_entry_with_xkcd_data(no_title_data)

    normalizer = Normalizer::XkcdNormalizer.new(feed_entry)
    post = normalizer.normalize

    # When no image title found and summary only contains image, content becomes empty
    assert_equal "", post.content
    # But post should be accepted because it has an image attachment
    assert_equal "enqueued", post.status
    assert_equal [], post.validation_errors
    # Should still extract the image as attachment
    assert_includes post.attachment_urls, "https://imgs.xkcd.com/comics/no_title.png"
  end

  test "handles HTML entities in title attributes" do
    entity_data = {
      "summary" => '<img src="https://imgs.xkcd.com/comics/entities.png" title="&lt;script&gt;alert(\'xss\')&lt;/script&gt; &amp; entities" />'
    }

    feed_entry = feed_entry_with_xkcd_data(entity_data)

    normalizer = Normalizer::XkcdNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_equal "<script>alert('xss')</script> & entities", post.content
  end

  test "accepts posts with images but no content" do
    image_only_data = {
      "id" => "https://example.com/image-only",
      "url" => "https://example.com/image-only",
      "summary" => '<img src="https://imgs.xkcd.com/comics/image_only.png" />',
      "content" => "",
      "title" => ""
    }

    feed_entry = feed_entry_with_xkcd_data(image_only_data)

    normalizer = Normalizer::XkcdNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_equal "", post.content
    assert_equal "enqueued", post.status
    assert_equal [], post.validation_errors
    assert_includes post.attachment_urls, "https://imgs.xkcd.com/comics/image_only.png"
  end

  test "accepts posts with text content but no images" do
    text_only_data = {
      "id" => "https://example.com/text-only",
      "url" => "https://example.com/text-only",
      "summary" => "<div>Some content</div>",
      "content" => "",
      "title" => ""
    }

    # Override to remove the default image
    feed_entry = create(:feed_entry, raw_data: text_only_data)

    normalizer = Normalizer::XkcdNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_equal "Some content", post.content
    assert_equal "enqueued", post.status
    assert_equal [], post.validation_errors
  end

  test "rejects posts with completely blank content and no images" do
    completely_blank_data = {
      "id" => "https://example.com/blank",
      "url" => "https://example.com/blank",
      "summary" => "",
      "content" => "",
      "title" => ""
    }

    feed_entry = create(:feed_entry, raw_data: completely_blank_data)

    normalizer = Normalizer::XkcdNormalizer.new(feed_entry)
    post = normalizer.normalize

    assert_equal "", post.content
    assert_equal [], post.attachment_urls
    assert_equal "rejected", post.status
    assert_includes post.validation_errors, "no_content_or_images"
  end
end
