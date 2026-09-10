require "test_helper"

class FeedAttachmentLimitTest < ActiveSupport::TestCase
  test "#normalize should omit gallery overflow and warn with the skipped count" do
    images = (1..21).map { |index| "https://images.example.com/panel-#{index}.png" }
    entry = build(:feed_entry, raw_data: {
      "title" => "Sample gallery",
      "link" => "https://example.com/gallery",
      "content" => images.map { |url| "<img src='#{url}'>" }.join
    })

    post = nil
    log = capture_log { post = Normalizer::RssNormalizer.new(entry).normalize }

    assert_equal "WARN: 1/21 attachments not published because of FreeFeed's 20-attachment limit. " \
                 "feed_id=#{entry.feed_id} uid=#{entry.uid}\n", log

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
    post = nil
    log = capture_log { post = Normalizer::WebhookNormalizer.new(entry).normalize }

    assert_equal "WARN: 2/22 attachments not published because of FreeFeed's 20-attachment limit. " \
                 "feed_id=#{entry.feed_id} uid=#{entry.uid}\n", log

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

    post = nil
    log = capture_log { post = Normalizer::RssNormalizer.new(entry).normalize }

    assert_empty log

    assert_equal images, post.attachment_urls
    assert_empty post.comments
  end

  private

  def capture_log
    io = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(io)
    Rails.logger.formatter = ->(severity, _time, _progname, message) { "#{severity}: #{message}\n" }
    yield
    io.string
  ensure
    Rails.logger = original
  end
end
