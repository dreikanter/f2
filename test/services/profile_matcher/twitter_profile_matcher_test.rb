require "test_helper"

class ProfileMatcher::TwitterProfileMatcherTest < ActiveSupport::TestCase
  def matcher(url)
    ProfileMatcher::TwitterProfileMatcher.new(url)
  end

  test ".match_specificity should be 100" do
    assert_equal 100, ProfileMatcher::TwitterProfileMatcher.match_specificity
  end

  test ".profile_key should be twitter" do
    assert_equal "twitter", ProfileMatcher::TwitterProfileMatcher.profile_key
  end

  test "#match? should match a twitter.com profile URL" do
    assert matcher("https://twitter.com/XDevelopers").match?
  end

  test "#match? should match an x.com profile URL" do
    assert matcher("https://x.com/XDevelopers").match?
  end

  test "#match? should match a mobile.twitter.com profile URL" do
    assert matcher("https://mobile.twitter.com/XDevelopers").match?
  end

  test "#match? should not match reserved paths" do
    assert_not matcher("https://x.com/home").match?
    assert_not matcher("https://twitter.com/search").match?
    assert_not matcher("https://x.com/i/lists/123").match?
  end

  test "#match? should not match the site root" do
    assert_not matcher("https://x.com/").match?
  end

  test "#match? should match a status URL by its handle segment" do
    # Only the first path segment matters; "XDevelopers" is a valid handle.
    assert matcher("https://x.com/XDevelopers/status/1").match?
  end

  test "#match? should not match non-twitter URLs" do
    assert_not matcher("https://example.com/XDevelopers").match?
  end

  test "#match? should handle blank input" do
    assert_not matcher("").match?
    assert_not matcher(nil).match?
  end
end
