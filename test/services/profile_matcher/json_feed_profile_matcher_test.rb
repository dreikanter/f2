require "test_helper"

class ProfileMatcher::JsonFeedProfileMatcherTest < ActiveSupport::TestCase
  def matcher(body)
    ProfileMatcher::JsonFeedProfileMatcher.new("https://example.com/feed.json", body)
  end

  test ".input_shape should be :url" do
    assert_equal :url, ProfileMatcher::JsonFeedProfileMatcher.input_shape
  end

  test ".match_specificity should be 10" do
    assert_equal 10, ProfileMatcher::JsonFeedProfileMatcher.match_specificity
  end

  test ".depends_on_ai should be false" do
    assert_equal false, ProfileMatcher::JsonFeedProfileMatcher.depends_on_ai
  end

  test ".profile_key should be json_feed" do
    assert_equal "json_feed", ProfileMatcher::JsonFeedProfileMatcher.profile_key
  end

  test "#match? should match a JSON Feed by its version marker" do
    body = file_fixture("feeds/json_feed/feed.json").read

    assert matcher(body).match?
  end

  test "#match? should match version 1.0 feeds" do
    body = '{"version":"https://jsonfeed.org/version/1","title":"Feed","items":[]}'

    assert matcher(body).match?
  end

  test "#match? should match when slashes are JSON-escaped" do
    body = '{"version":"https:\/\/jsonfeed.org\/version\/1.1","title":"Feed"}'

    assert matcher(body).match?
  end

  test "#match? should not match RSS or Atom XML" do
    assert_not matcher('<?xml version="1.0"?><rss version="2.0"><channel></channel></rss>').match?
    assert_not matcher('<feed xmlns="http://www.w3.org/2005/Atom"></feed>').match?
  end

  test "#match? should not match plain JSON without the marker" do
    assert_not matcher('{"title":"Just some JSON","items":[]}').match?
  end

  test "#match? should handle a blank fetched_body" do
    assert_not matcher("").match?
    assert_not matcher(nil).match?
  end
end
