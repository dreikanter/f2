require "test_helper"

class ProfileMatcher::BlueskyProfileMatcherTest < ActiveSupport::TestCase
  def matcher(url)
    ProfileMatcher::BlueskyProfileMatcher.new(url)
  end

  test ".match_specificity should be 100" do
    assert_equal 100, ProfileMatcher::BlueskyProfileMatcher.match_specificity
  end

  test ".profile_key should be bluesky" do
    assert_equal "bluesky", ProfileMatcher::BlueskyProfileMatcher.profile_key
  end

  test "#match? should match a bsky.app profile URL" do
    assert matcher("https://bsky.app/profile/testuser.bsky.social").match?
  end

  test "#match? should match a profile URL with a custom-domain handle" do
    assert matcher("https://bsky.app/profile/example.com").match?
  end

  test "#match? should match a profile URL with a DID" do
    assert matcher("https://bsky.app/profile/did:plc:abc123").match?
  end

  test "#match? should match a post URL by its profile segment" do
    assert matcher("https://bsky.app/profile/testuser.bsky.social/post/3aaa").match?
  end

  test "#match? should not match other bsky.app paths" do
    assert_not matcher("https://bsky.app/search").match?
    assert_not matcher("https://bsky.app/feeds").match?
    assert_not matcher("https://bsky.app/settings").match?
  end

  test "#match? should not match a profile path without an actor" do
    assert_not matcher("https://bsky.app/profile/").match?
  end

  test "#match? should not match a profile whose actor is not a handle or DID" do
    assert_not matcher("https://bsky.app/profile/justname").match?
  end

  test "#match? should not match the site root" do
    assert_not matcher("https://bsky.app/").match?
  end

  test "#match? should not match non-bsky URLs" do
    assert_not matcher("https://example.com/profile/testuser.bsky.social").match?
  end

  test "#match? should handle blank input" do
    assert_not matcher("").match?
    assert_not matcher(nil).match?
  end
end
