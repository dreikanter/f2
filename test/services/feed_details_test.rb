require "test_helper"

class FeedDetailsTest < ActiveSupport::TestCase
  setup do
    @cache = ActiveSupport::Cache::MemoryStore.new
    @logger = ActiveSupport::Logger.new(nil) # Silent logger for tests
  end

  def user
    @user ||= create(:user)
  end

  def cache_key(url)
    FeedIdentificationCache.key_for(user.id, url)
  end

  test "#identify should successfully identify RSS feed and update cache" do
    url = "http://example.com/feed.xml"

    rss_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test RSS Feed</title>
          <description>Test Description</description>
          <link>http://example.com</link>
          <item>
            <title>Test Post</title>
            <description>Test content</description>
            <link>http://example.com/post1</link>
          </item>
        </channel>
      </rss>
    XML

    stub_request(:get, url)
      .to_return(status: 200, body: rss_content, headers: { "Content-Type" => "application/xml" })

    service = FeedDetails.new(user: user, url: url, cache: @cache, logger: @logger)
    service.identify

    cached_data = @cache.read(cache_key(url))
    assert_not_nil cached_data
    assert_equal "success", cached_data[:status]
    assert_equal url, cached_data[:url]
    assert_equal "rss", cached_data[:feed_profile_key]
    assert_equal "Test RSS Feed", cached_data[:title]
  end

  test "#identify should successfully identify XKCD feed and update cache" do
    url = "https://xkcd.com/rss.xml"

    rss_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>xkcd.com</title>
          <link>https://xkcd.com/</link>
          <description>xkcd.com: A webcomic</description>
        </channel>
      </rss>
    XML

    stub_request(:get, url)
      .to_return(status: 200, body: rss_content, headers: { "Content-Type" => "application/xml" })

    service = FeedDetails.new(user: user, url: url, cache: @cache, logger: @logger)
    service.identify

    cached_data = @cache.read(cache_key(url))
    assert_not_nil cached_data
    assert_equal "success", cached_data[:status]
    assert_equal "xkcd", cached_data[:feed_profile_key]
  end

  test "#identify should handle title extraction failure gracefully" do
    url = "http://example.com/feed.xml"

    rss_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <description>Test Description</description>
        </channel>
      </rss>
    XML

    stub_request(:get, url)
      .to_return(status: 200, body: rss_content, headers: { "Content-Type" => "application/xml" })

    service = FeedDetails.new(user: user, url: url, cache: @cache, logger: @logger)
    service.identify

    cached_data = @cache.read(cache_key(url))
    assert_not_nil cached_data
    assert_equal "success", cached_data[:status]
    assert_nil cached_data[:title]
  end

  test "#identify should update cache with failed status when profile not identified" do
    url = "http://example.com/unknown.txt"

    stub_request(:get, url)
      .to_return(status: 200, body: "Not a valid feed format", headers: { "Content-Type" => "text/plain" })

    service = FeedDetails.new(user: user, url: url, cache: @cache, logger: @logger)
    service.identify

    cached_data = @cache.read(cache_key(url))
    assert_not_nil cached_data
    assert_equal "failed", cached_data[:status]
    assert_equal "Could not identify feed profile", cached_data[:error]
  end

  test "#identify should update cache with failed status on HTTP errors" do
    url = "http://example.com/error.xml"

    stub_request(:get, url)
      .to_return(status: 500, body: "Internal Server Error")

    service = FeedDetails.new(user: user, url: url, cache: @cache, logger: @logger)
    service.identify

    cached_data = @cache.read(cache_key(url))
    assert_not_nil cached_data
    assert_equal "failed", cached_data[:status]
    assert_includes cached_data[:error], "An error occurred while identifying the feed"
  end

  test "#identify should handle network errors gracefully" do
    url = "http://example.com/timeout.xml"

    stub_request(:get, url)
      .to_raise(HttpClient::TimeoutError.new("Connection timeout"))

    service = FeedDetails.new(user: user, url: url, cache: @cache, logger: @logger)
    service.identify

    cached_data = @cache.read(cache_key(url))
    assert_not_nil cached_data
    assert_equal "failed", cached_data[:status]
    assert_equal "An error occurred while identifying the feed", cached_data[:error]
  end

  test "#identify should use correct cache key format" do
    url = "http://example.com/feed.xml"

    rss_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
        </channel>
      </rss>
    XML

    stub_request(:get, url)
      .to_return(status: 200, body: rss_content, headers: { "Content-Type" => "application/xml" })

    service = FeedDetails.new(user: user, url: url, cache: @cache, logger: @logger)
    service.identify

    expected_cache_key = "feed_identification/#{user.id}/#{Digest::SHA256.hexdigest(url)}"
    assert_not_nil @cache.read(expected_cache_key)
  end

  test "#identify should cache results for 10 minutes" do
    url = "http://example.com/feed.xml"

    rss_content = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <rss version="2.0">
        <channel>
          <title>Test Feed</title>
        </channel>
      </rss>
    XML

    stub_request(:get, url)
      .to_return(status: 200, body: rss_content, headers: { "Content-Type" => "application/xml" })

    # Mock cache.write to verify expires_in parameter
    original_write = @cache.method(:write)
    write_called_with = nil

    @cache.stub(:write, ->(key, value, options = {}) {
      write_called_with = options if key == cache_key(url)
      original_write.call(key, value, options)
    }) do
      service = FeedDetails.new(user: user, url: url, cache: @cache, logger: @logger)
      service.identify
    end

    assert_equal 10.minutes, write_called_with[:expires_in]
  end
end
