require "test_helper"

class RssContentTest < ActiveSupport::TestCase
  test "RSS content extension should preserve the title body links and ordered images" do
    entry, post = normalize_fixture("full_content.xml")

    assert_equal "discovery-123", entry.uid
    assert_equal Time.iso8601("2026-09-09T10:30:00Z"), entry.published_at
    assert_equal entry.published_at, post.published_at
    assert_equal "Sample discovery\n\nFull explanation.\n\nRead the paper (https://research.example.org/paper). - https://journal.example.com/discovery", post.content
    assert_equal ["https://journal.example.com/first.png", "https://journal.example.com/second.png"], post.attachment_urls
    assert post.enqueued?
  end

  test "Atom content should take precedence over its summary without losing the title" do
    entry, post = normalize_fixture("full_content.atom")

    assert_equal "urn:sample:essay", entry.uid
    assert_equal Time.iso8601("2026-09-09T10:30:00Z"), entry.published_at
    assert_equal "Sample essay\n\nFirst paragraph.\n\nA reference (https://reference.example.com/). - https://essays.example.org/essay", post.content
    assert_equal "https://essays.example.org/essay", post.source_url
    assert post.enqueued?
  end

  private

  def normalize_fixture(filename)
    feed = build(:feed, feed_profile_key: "rss", url: "https://example.com/feed")
    stub_request(:get, feed.url).to_return(body: file_fixture("feeds/rss/#{filename}").read)
    entry = feed.processor_instance(feed.loader_instance.load).process.entries.sole
    [entry, feed.normalizer_instance(entry).normalize]
  end
end
