require "test_helper"

class ProfileMatcher::TheycantalkProfileMatcherTest < ActiveSupport::TestCase
  def matcher(url)
    ProfileMatcher::TheycantalkProfileMatcher.new(url)
  end

  test ".input_shape should be :url" do
    assert_equal :url, ProfileMatcher::TheycantalkProfileMatcher.input_shape
  end

  test ".match_specificity should be 100" do
    assert_equal 100, ProfileMatcher::TheycantalkProfileMatcher.match_specificity
  end

  test ".depends_on_ai should be false" do
    assert_equal false, ProfileMatcher::TheycantalkProfileMatcher.depends_on_ai
  end

  test "#match? should match theycantalk.com URLs" do
    assert matcher("http://theycantalk.com/rss").match?
  end

  test "#match? should match www.theycantalk.com URLs" do
    assert matcher("https://www.theycantalk.com/feed").match?
  end

  test "#match? should match feedburner URLs containing theycantalk in path" do
    assert matcher("https://feeds.feedburner.com/theycantalk/xFcE").match?
  end

  test "#match? should not match theycantalk subdomains other than www" do
    assert_not matcher("https://cdn.theycantalk.com/feed").match?
  end

  test "#match? should not match feedburner subdomains other than feeds" do
    assert_not matcher("https://other.feedburner.com/theycantalk/xFcE").match?
  end

  test "#match? should not match feedburner URLs without theycantalk in path" do
    assert_not matcher("https://feeds.feedburner.com/someotherfeed/abc").match?
  end

  test "#match? should not match non-theycantalk URLs" do
    assert_not matcher("https://example.com/feed.xml").match?
  end

  test "#match? should not match URLs that contain theycantalk only in path on other domains" do
    assert_not matcher("https://example.com/theycantalk/feed").match?
  end

  test "#match? should handle blank inputs" do
    assert_not matcher("").match?
    assert_not matcher(nil).match?
  end

  test "#match? should raise error for invalid URLs" do
    assert_raises(URI::InvalidURIError) do
      matcher("not a url").match?
    end
  end
end
