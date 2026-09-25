require "test_helper"

class Loader::HttpThrottlingTest < ActiveSupport::TestCase
  test "#load should share a cooldown across feeds on the same host and recover after it expires" do
    freeze_time
    first = create(:feed, url: "https://example.com/first.xml")
    second = create(:feed, url: "https://example.com/second.xml")
    limited = stub_request(:get, first.url).to_return(status: 429, headers: { "Retry-After" => "120" })
    recovered = stub_request(:get, second.url).to_return(body: "feed contents")

    error = assert_raises(Loader::Throttled) { Loader::HttpLoader.new(first).load }
    assert_equal 429, error.http_status
    assert_equal 120, error.retry_after

    travel 30.seconds
    error = assert_raises(Loader::Throttled) { Loader::HttpLoader.new(second).load }
    assert_equal 90, error.retry_after
    assert_nil error.http_status
    assert_not_requested recovered

    travel 91.seconds
    assert_equal "feed contents", Loader::HttpLoader.new(second).load
    assert_requested limited, times: 1
    assert_requested recovered, times: 1
  end

  test "#load should leave other hosts available during a cooldown" do
    first = create(:feed, url: "https://example.com/feed.xml")
    second = create(:feed, url: "https://other.example/feed.xml")
    stub_request(:get, first.url).to_return(status: 429)
    request = stub_request(:get, second.url).to_return(body: "feed contents")

    assert_raises(Loader::Throttled) { Loader::HttpLoader.new(first).load }

    assert_equal "feed contents", Loader::HttpLoader.new(second).load
    assert_requested request, times: 1
  end

  test "#load should retain the responding host and cool down both sides of a redirect" do
    feed = create(:feed, url: "https://example.com/feed.xml")
    redirect = stub_request(:get, feed.url).to_return(status: 302, headers: { "Location" => "https://feeds.example/rss" })
    limited = stub_request(:get, "https://feeds.example/rss").to_return(status: 429)

    error = assert_raises(Loader::Throttled) { Loader::HttpLoader.new(feed).load }

    assert_equal "feeds.example", error.source_host
    assert_raises(Loader::Throttled) { Loader::HttpLoader.new(feed).load }
    direct_feed = create(:feed, url: "https://feeds.example/rss")
    assert_raises(Loader::Throttled) { Loader::HttpLoader.new(direct_feed).load }
    assert_requested redirect, times: 1
    assert_requested limited, times: 1
  end

  test "#load should classify throttling from a profile-specific HTTP endpoint" do
    feed = create(:feed, feed_profile_key: "twitter", url: "https://x.com/example")
    stub_request(:get, "https://syndication.twitter.com/srv/timeline-profile/screen-name/example").to_return(status: 429)

    error = assert_raises(Loader::Throttled) { feed.loader_instance.load }

    assert_equal "syndication.twitter.com", error.source_host
    assert_equal 429, error.http_status
  end
end
