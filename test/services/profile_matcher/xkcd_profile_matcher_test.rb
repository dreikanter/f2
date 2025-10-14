require "test_helper"

class ProfileMatcher::XkcdProfileMatcherTest < ActiveSupport::TestCase
  def response
    @response ||= HttpClient::Response.new(status: 200, body: "ignore")
  end

  def matcher(url)
    ProfileMatcher::XkcdProfileMatcher.new(url, response)
  end

  test "should match xkcd.com URLs" do
    assert matcher("https://xkcd.com/rss.xml").match?
  end

  test "should match xkcd.com subdomains" do
    assert matcher("https://www.xkcd.com/rss.xml").match?
  end

  test "should not match non-xkcd URLs" do
    assert_not matcher("https://example.com/feed.xml").match?
  end

  test "should not match URLs that just contain xkcd in path" do
    assert_not matcher("https://example.com/xkcd.com/feed.xml").match?
  end

  test "should handle blank URLs" do
    assert_not matcher("").match?
    assert_not matcher(nil).match?
  end

  test "should raise error for invalid URLs" do
    assert_raises(URI::InvalidURIError) do
      matcher("not a url").match?
    end
  end
end
