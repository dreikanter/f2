require "test_helper"

class ProfileMatcher::TomorrowsProfileMatcherTest < ActiveSupport::TestCase
  def matcher(url)
    ProfileMatcher::TomorrowsProfileMatcher.new(url)
  end

  test ".input_shape should be :url" do
    assert_equal :url, ProfileMatcher::TomorrowsProfileMatcher.input_shape
  end

  test ".match_specificity should be 100" do
    # Higher than RSS (10) so 365tomorrows.com URLs prefer the Tomorrows profile.
    assert_equal 100, ProfileMatcher::TomorrowsProfileMatcher.match_specificity
  end

  test ".depends_on_ai should be false" do
    assert_equal false, ProfileMatcher::TomorrowsProfileMatcher.depends_on_ai
  end

  test "#match? should match 365tomorrows.com feed URL" do
    assert matcher("https://365tomorrows.com/feed/").match?
  end

  test "#match? should match www.365tomorrows.com feed URL" do
    assert matcher("https://www.365tomorrows.com/feed/").match?
  end

  test "#match? should not match arbitrary subdomains" do
    assert_not matcher("https://other.365tomorrows.com/feed/").match?
  end

  test "#match? should not match non-tomorrows URLs" do
    assert_not matcher("https://example.com/feed.xml").match?
  end

  test "#match? should not match URLs that just contain 365tomorrows in path" do
    assert_not matcher("https://example.com/365tomorrows.com/feed/").match?
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
