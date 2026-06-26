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

  test "#match? should match a JSON Feed by its version, title, and items" do
    body = file_fixture("feeds/json_feed/feed.json").read

    assert matcher(body).match?
  end

  test "#match? should match version 1.0 feeds with an empty items array" do
    body = '{"version":"https://jsonfeed.org/version/1","title":"Feed","items":[]}'

    assert matcher(body).match?
  end

  test "#match? should match when slashes are JSON-escaped" do
    body = '{"version":"https:\/\/jsonfeed.org\/version\/1.1","title":"Feed","items":[]}'

    assert matcher(body).match?
  end

  test "#match? should not match RSS or Atom XML" do
    assert_not matcher('<?xml version="1.0"?><rss version="2.0"><channel></channel></rss>').match?
    assert_not matcher('<feed xmlns="http://www.w3.org/2005/Atom"></feed>').match?
  end

  test "#match? should not match an HTML page that links to the spec" do
    body = '<html><body><a href="https://jsonfeed.org/version/1.1">JSON Feed</a></body></html>'

    assert_not matcher(body).match?
  end

  test "#match? should not match plain JSON without the version marker" do
    assert_not matcher('{"title":"Just some JSON","items":[]}').match?
  end

  test "#match? should not match when the marker is outside the version field" do
    body = '{"version":"1.1","description":"Built per https://jsonfeed.org/version/1.1","title":"Feed","items":[]}'

    assert_not matcher(body).match?
  end

  test "#match? should not match a lookalike host in the version URL" do
    embedded = '{"version":"https://evil.com/jsonfeed.org/version/1.1","title":"Feed","items":[]}'
    suffixed = '{"version":"https://notjsonfeed.org/version/1","title":"Feed","items":[]}'

    assert_not matcher(embedded).match?
    assert_not matcher(suffixed).match?
  end

  test "#match? should not match a version without a scheme" do
    body = '{"version":"jsonfeed.org/version/1.1","title":"Feed","items":[]}'

    assert_not matcher(body).match?
  end

  test "#match? should not match a JSON array" do
    body = '[{"version":"https://jsonfeed.org/version/1.1","title":"Feed","items":[]}]'

    assert_not matcher(body).match?
  end

  test "#match? should not match when items is missing or not an array" do
    assert_not matcher('{"version":"https://jsonfeed.org/version/1.1","title":"Feed"}').match?
    assert_not matcher('{"version":"https://jsonfeed.org/version/1.1","title":"Feed","items":"nope"}').match?
  end

  test "#match? should not match when the title is missing" do
    body = '{"version":"https://jsonfeed.org/version/1.1","items":[]}'

    assert_not matcher(body).match?
  end

  test "#match? should handle a blank fetched_body" do
    assert_not matcher("").match?
    assert_not matcher(nil).match?
  end

  test "#match? should not match malformed JSON" do
    assert_not matcher('{"version":"https://jsonfeed.org/version/1.1", "title":').match?
  end
end
