require "test_helper"

class ProfileMatcher::MonkeyuserProfileMatcherTest < ActiveSupport::TestCase
  def matcher(url)
    ProfileMatcher::MonkeyuserProfileMatcher.new(url)
  end

  test ".input_shape should be :url" do
    assert_equal :url, ProfileMatcher::MonkeyuserProfileMatcher.input_shape
  end

  test ".match_specificity should be 100" do
    # Higher than RSS (10) so monkeyuser.com URLs prefer the MonkeyUser profile.
    assert_equal 100, ProfileMatcher::MonkeyuserProfileMatcher.match_specificity
  end

  test ".depends_on_ai should be false" do
    assert_equal false, ProfileMatcher::MonkeyuserProfileMatcher.depends_on_ai
  end

  test "#match? should match monkeyuser.com URLs" do
    assert matcher("https://monkeyuser.com/index.xml").match?
  end

  test "#match? should match monkeyuser.com subdomains" do
    assert matcher("https://www.monkeyuser.com/index.xml").match?
  end

  test "#match? should not match non-monkeyuser URLs" do
    assert_not matcher("https://example.com/feed.xml").match?
  end

  test "#match? should not match URLs that just contain monkeyuser in path" do
    assert_not matcher("https://example.com/monkeyuser.com/feed.xml").match?
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
