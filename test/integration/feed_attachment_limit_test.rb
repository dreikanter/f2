require "test_helper"

class FeedAttachmentLimitTest < ActiveSupport::TestCase
  test "#normalize should omit gallery overflow" do
    images = (1..21).map { |index| "https://images.example.com/panel-#{index}.png" }
    entry = build(:feed_entry, raw_data: {
      "title" => "Sample gallery",
      "link" => "https://example.com/gallery",
      "content" => images.map { |url| "<img src='#{url}'>" }.join
    })

    post = Normalizer::RssNormalizer.new(entry).normalize

    assert_equal images.first(20), post.attachment_urls
    assert_empty post.comments
    assert post.enqueued?
  end

  test "#normalize should preserve source comments when omitting multiple attachments" do
    images = (1..22).map { |index| "https://images.example.com/panel-#{index}.png" }
    entry = build(:feed_entry, raw_data: {
      "content" => "Sample gallery",
      "source_url" => "https://example.com/gallery",
      "images" => images,
      "comments" => ["First caption", "Second caption"]
    })

    post = Normalizer::WebhookNormalizer.new(entry).normalize

    assert_equal images.first(20), post.attachment_urls
    assert_equal ["First caption", "Second caption"], post.comments
  end

  test "#normalize should discard unsafe images before counting the attachment limit" do
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
