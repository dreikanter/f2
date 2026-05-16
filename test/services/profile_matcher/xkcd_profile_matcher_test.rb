require "test_helper"

class ProfileMatcher::XkcdProfileMatcherTest < ActiveSupport::TestCase
  def matcher(url)
    ProfileMatcher::XkcdProfileMatcher.new(url)
  end

  test ".input_shape should be :url" do
    assert_equal :url, ProfileMatcher::XkcdProfileMatcher.input_shape
  end

  test ".match_specificity should be 100" do
    # Higher than RSS (10) so xkcd.com URLs prefer the XKCD profile.
    assert_equal 100, ProfileMatcher::XkcdProfileMatcher.match_specificity
  end

  test ".depends_on_ai should be false" do
    assert_equal false, ProfileMatcher::XkcdProfileMatcher.depends_on_ai
  end

  test "#match? should match xkcd.com URLs" do
    assert matcher("https://xkcd.com/rss.xml").match?
  end

  test "#match? should match xkcd.com subdomains" do
    assert matcher("https://www.xkcd.com/rss.xml").match?
  end

  test "#match? should not match non-xkcd URLs" do
    assert_not matcher("https://example.com/feed.xml").match?
  end

  test "#match? should not match URLs that just contain xkcd in path" do
    assert_not matcher("https://example.com/xkcd.com/feed.xml").match?
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
