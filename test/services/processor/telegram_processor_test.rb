require "test_helper"

class Processor::TelegramProcessorTest < ActiveSupport::TestCase
  def feed
    @feed ||= create(:feed, feed_profile_key: "telegram", url: "testchannel")
  end

  def sample_html
    @sample_html ||= file_fixture("feeds/telegram/channel.html").read
  end

  def entries
    @entries ||= Processor::TelegramProcessor.new(feed, sample_html).process.entries
  end

  def message_html(text_html)
    <<~HTML
      <div class="tgme_widget_message_wrap">
        <div class="tgme_widget_message" data-post="testchannel/9">
          <div class="tgme_widget_message_text">#{text_html}</div>
          <a class="tgme_widget_message_date" href="https://t.me/testchannel/9">
            <time datetime="2026-06-01T12:00:00+00:00"></time>
          </a>
        </div>
      </div>
    HTML
  end

  def link_from(html)
    entry = Processor::TelegramProcessor.new(feed, html).process.entries.sole
    Nokogiri::HTML::DocumentFragment.parse(entry.raw_data["text_html"]).at_css("a")
  end

  test "#process should create a FeedEntry per message with a data-post id" do
    assert_equal 4, entries.size
    assert entries.all? { |entry| entry.is_a?(FeedEntry) }
    assert entries.all? { |entry| entry.feed == feed }
    assert entries.all? { |entry| entry.status == "pending" }
  end

  test "#process should skip service messages without a data-post id" do
    assert_not_includes entries.map(&:uid), nil
    assert_equal %w[testchannel/1 testchannel/2 testchannel/3 testchannel/4], entries.map(&:uid)
  end

  test "#process should store the message permalink and text html" do
    entry = entries.first

    assert_equal "https://t.me/testchannel/1", entry.raw_data["url"]
    assert_includes entry.raw_data["text_html"], "Hello"
    assert_includes entry.raw_data["text_html"], "<br>"
  end

  test "#process should extract photo URLs from the background-image style" do
    photo_entry = entries[1]

    assert_equal ["https://cdn-test.telesco.pe/file/photo2.jpg"], photo_entry.raw_data["images"]
  end

  test "#process should extract video thumbnail URLs" do
    video_entry = entries[2]

    assert_equal ["https://cdn-test.telesco.pe/file/vthumb3.jpg"], video_entry.raw_data["images"]
  end

  test "#process should unescape the ampersands t.me escaped twice in a link" do
    link_html = entries[3].raw_data["text_html"]
    anchor = Nokogiri::HTML::DocumentFragment.parse(link_html).at_css("a")

    assert_equal "https://example.com/tickets?utm_source=tg&utm_campaign=spring", anchor["href"]
    assert_equal "https://example.com/tickets?utm_source=tg&utm_campaign=spring", anchor.text
  end

  test "#process should leave a correctly escaped link URL alone" do
    html = message_html(%(<a href="https://example.com/?a=1&amp;b=2">https://example.com/?a=1&amp;b=2</a>))
    anchor = link_from(html)

    assert_equal "https://example.com/?a=1&b=2", anchor["href"]
    assert_equal "https://example.com/?a=1&b=2", anchor.text
  end

  test "#process should keep link captions as written" do
    html = message_html(%(<a href="https://example.com/?a=1&amp;amp;b=2">Tea &amp;amp; coffee</a>))
    anchor = link_from(html)

    assert_equal "https://example.com/?a=1&b=2", anchor["href"]
    assert_equal "Tea &amp; coffee", anchor.text
  end

  test "#process should use the dated time, not the video duration, for published_at" do
    video_entry = entries[2]

    assert_equal Time.utc(2026, 6, 1, 12, 10, 0), video_entry.published_at
  end
end
