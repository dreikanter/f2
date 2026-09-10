require "test_helper"

class FeedAttachmentLimitTest < ActiveSupport::TestCase
  test "normalization should preserve gallery overflow as ordered image links" do
    images = (1..22).map { |index| "https://images.example.com/panel-#{index}.png" }
    entry = build(:feed_entry, raw_data: {
      "title" => "Sample gallery",
      "link" => "https://example.com/gallery",
      "content" => images.map { |url| "<img src='#{url}'>" }.join
    })

    post = Normalizer::RssNormalizer.new(entry).normalize

    assert_equal images.first(20), post.attachment_urls
    assert_equal ["https://images.example.com/panel-21.png", "https://images.example.com/panel-22.png"], post.comments
    assert post.enqueued?
  end

  test "normalization should discard unsafe images before counting the attachment limit" do
    images = (1..20).map { |index| "https://images.example.com/panel-#{index}.png" }
    entry = build(:feed_entry, raw_data: {
      "title" => "Sample gallery",
      "link" => "https://example.com/gallery",
      "enclosures" => [{ "url" => "file:///etc/passwd" }] + images.map { |url| { "url" => url } }
    })

    post = Normalizer::RssNormalizer.new(entry).normalize

    assert_equal images, post.attachment_urls
    assert_empty post.comments
  end
end
