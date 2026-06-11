require "test_helper"

class ProfileMatcher::AerostatProfileMatcherTest < ActiveSupport::TestCase
  def matcher(url)
    ProfileMatcher::AerostatProfileMatcher.new(url)
  end

  test ".input_shape should be :url" do
    assert_equal :url, ProfileMatcher::AerostatProfileMatcher.input_shape
  end

  test ".match_specificity should be 100" do
    # Higher than RSS (10) so aerostatbg.ru URLs prefer the Aerostat profile.
    assert_equal 100, ProfileMatcher::AerostatProfileMatcher.match_specificity
  end

  test ".depends_on_ai should be false" do
    assert_equal false, ProfileMatcher::AerostatProfileMatcher.depends_on_ai
  end

  test "#match? should match aerostatbg.ru URLs" do
    assert matcher("https://aerostatbg.ru/rss.xml").match?
  end

  test "#match? should match aerostatbg.ru subdomains" do
    assert matcher("https://www.aerostatbg.ru/rss.xml").match?
  end

  test "#match? should not match non-aerostat URLs" do
    assert_not matcher("https://example.com/feed.xml").match?
  end

  test "#match? should not match URLs that just contain aerostatbg.ru in path" do
    assert_not matcher("https://example.com/aerostatbg.ru/feed.xml").match?
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
