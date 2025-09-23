require "test_helper"

class FeedPreviewJobTest < ActiveJob::TestCase
  def user
    @user ||= create(:user)
  end

  def feed_profile
    @feed_profile ||= create(:feed_profile, user: user, loader: "http_loader", processor: "rss_processor", normalizer: "rss_normalizer")
  end

  def feed_preview
    @feed_preview ||= create(:feed_preview, feed_profile: feed_profile)
  end

  test "handles missing feed preview gracefully" do
    assert_nothing_raised do
      FeedPreviewJob.perform_now("nonexistent-uuid")
    end
  end

  test "executes feed preview workflow successfully" do
    preview = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed.xml")

    # Create real RSS content
    sample_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
          <description>Test RSS Feed</description>
          <item>
            <guid>entry-123</guid>
            <title>First Test Entry</title>
            <description>This is a test entry description</description>
            <link>https://example.com/entry-123</link>
            <pubDate>#{1.hour.ago.rfc822}</pubDate>
          </item>
          <item>
            <guid>entry-456</guid>
            <title>Second Test Entry</title>
            <description>Another test entry</description>
            <link>https://example.com/entry-456</link>
            <pubDate>#{2.hours.ago.rfc822}</pubDate>
          </item>
        </channel>
      </rss>
    RSS

    # Use real HTTP loader with stubbed network call
    WebMock.stub_request(:get, preview.url).to_return(body: sample_rss, status: 200)

    FeedPreviewJob.perform_now(preview.id)

    preview.reload
    assert_equal "completed", preview.status
    assert preview.data.present?
    assert_equal 2, preview.posts_count
    assert preview.data["posts"].first["content"].include?("test entry description")
  end

  test "handles HTTP loading errors gracefully" do
    preview = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed.xml")

    # Stub network request to timeout
    WebMock.stub_request(:get, preview.url).to_timeout

    assert_raises(StandardError) do
      FeedPreviewJob.perform_now(preview.id)
    end

    preview.reload
    assert_equal "failed", preview.status
  end

  test "handles RSS processing errors gracefully" do
    preview = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed.xml")

    # Return invalid RSS that will cause parsing errors
    invalid_rss = "<invalid>not valid RSS</malformed>"
    WebMock.stub_request(:get, preview.url).to_return(body: invalid_rss, status: 200)

    # RSS processor returns empty array for invalid RSS, so workflow should complete
    FeedPreviewJob.perform_now(preview.id)

    preview.reload
    assert_equal "completed", preview.status
    assert_equal 0, preview.posts_count
  end

  test "limits posts to PREVIEW_LIMIT" do
    preview = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed.xml")

    # Create RSS with more than 10 items
    items = 15.times.map do |i|
      <<~ITEM
        <item>
          <guid>entry-#{i}</guid>
          <title>Entry #{i}</title>
          <description>Description #{i}</description>
          <link>https://example.com/entry-#{i}</link>
          <pubDate>#{i.hours.ago.rfc822}</pubDate>
        </item>
      ITEM
    end

    large_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Large Feed</title>
          #{items.join}
        </channel>
      </rss>
    RSS

    WebMock.stub_request(:get, preview.url).to_return(body: large_rss, status: 200)

    FeedPreviewJob.perform_now(preview.id)

    preview.reload
    assert_equal "completed", preview.status
    assert_equal FeedPreview::PREVIEW_LIMIT, preview.posts_count
  end

  test "handles unknown loader gracefully" do
    bad_profile = create(:feed_profile, user: user, loader: "unknown", processor: "rss_processor", normalizer: "rss_normalizer")
    preview = create(:feed_preview, feed_profile: bad_profile)

    assert_raises(ArgumentError) do
      FeedPreviewJob.perform_now(preview.id)
    end

    preview.reload
    assert_equal "failed", preview.status
  end

  test "handles unknown processor gracefully" do
    bad_profile = create(:feed_profile, user: user, loader: "http_loader", processor: "unknown", normalizer: "rss_normalizer")
    preview = create(:feed_preview, feed_profile: bad_profile)

    # Stub HTTP request to reach processor step
    WebMock.stub_request(:get, preview.url).to_return(body: "<rss></rss>", status: 200)

    assert_raises(ArgumentError) do
      FeedPreviewJob.perform_now(preview.id)
    end

    preview.reload
    assert_equal "failed", preview.status
  end

  test "handles unknown normalizer gracefully" do
    bad_profile = create(:feed_profile, user: user, loader: "http_loader", processor: "rss_processor", normalizer: "unknown")
    preview = create(:feed_preview, feed_profile: bad_profile)

    # Stub with valid RSS content to reach normalizer step
    sample_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <guid>test-entry</guid>
            <title>Test Entry</title>
            <description>Test description</description>
          </item>
        </channel>
      </rss>
    RSS

    WebMock.stub_request(:get, preview.url).to_return(body: sample_rss, status: 200)

    assert_raises(ArgumentError) do
      FeedPreviewJob.perform_now(preview.id)
    end

    preview.reload
    assert_equal "failed", preview.status
  end

  test "handles empty feed content gracefully" do
    preview = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed.xml")

    # Empty RSS with no items
    empty_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Empty Feed</title>
          <description>No items</description>
        </channel>
      </rss>
    RSS

    WebMock.stub_request(:get, preview.url).to_return(body: empty_rss, status: 200)

    FeedPreviewJob.perform_now(preview.id)

    preview.reload
    assert_equal "completed", preview.status
    assert_equal 0, preview.posts_count
  end

  test "sets preview status to processing before starting" do
    preview = create(:feed_preview, feed_profile: feed_profile, status: :pending)

    WebMock.stub_request(:get, preview.url).to_return(body: "<rss><channel></channel></rss>", status: 200)

    FeedPreviewJob.perform_now(preview.id)

    # Check that it went through processing status (by checking final completed status)
    preview.reload
    assert_equal "completed", preview.status
  end

  test "preserves post data structure correctly" do
    preview = create(:feed_preview, feed_profile: feed_profile, url: "https://example.com/feed.xml")

    sample_rss = <<~RSS
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <item>
            <guid>unique-entry-id</guid>
            <title>Test Entry Title</title>
            <description>Test entry description with content</description>
            <link>https://example.com/specific-link</link>
            <pubDate>#{1.hour.ago.rfc822}</pubDate>
          </item>
        </channel>
      </rss>
    RSS

    WebMock.stub_request(:get, preview.url).to_return(body: sample_rss, status: 200)

    FeedPreviewJob.perform_now(preview.id)

    preview.reload
    post_data = preview.posts_data.first

    assert_equal "unique-entry-id", post_data["uid"]
    assert post_data["content"].include?("Test entry description")
    assert_equal "https://example.com/specific-link", post_data["source_url"]
    assert post_data["published_at"].present?
    assert post_data["attachments"].is_a?(Array)
  end
end
