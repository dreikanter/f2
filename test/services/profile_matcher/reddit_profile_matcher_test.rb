require "test_helper"

class ProfileMatcher::RedditProfileMatcherTest < ActiveSupport::TestCase
  def matcher(url)
    ProfileMatcher::RedditProfileMatcher.new(url)
  end

  test ".input_shape should be :url" do
    assert_equal :url, ProfileMatcher::RedditProfileMatcher.input_shape
  end

  test ".match_specificity should be 50" do
    # Higher than RSS (10) so reddit.com URLs prefer the Reddit profile.
    assert_equal 50, ProfileMatcher::RedditProfileMatcher.match_specificity
  end

  test ".depends_on_ai should be false" do
    assert_equal false, ProfileMatcher::RedditProfileMatcher.depends_on_ai
  end

  test "#match? should match subreddit RSS URLs" do
    assert matcher("https://www.reddit.com/r/programming/.rss").match?
  end

  test "#match? should match subreddit page URLs" do
    assert matcher("https://www.reddit.com/r/programming/").match?
  end

  test "#match? should match user page RSS URLs" do
    assert matcher("https://www.reddit.com/user/someuser/.rss").match?
  end

  test "#match? should match reddit.com without www" do
    assert matcher("https://reddit.com/r/ruby/").match?
  end

  test "#match? should match old.reddit.com URLs" do
    assert matcher("https://old.reddit.com/r/ruby/").match?
  end

  test "#match? should match short subreddit names like r/worldnews" do
    assert matcher("r/worldnews").match?
  end

  test "#match? should match short user names like user/someuser" do
    assert matcher("user/someuser").match?
  end

  test "#match? should not match reddit.com homepage" do
    assert_not matcher("https://www.reddit.com/").match?
  end

  test "#match? should not match non-reddit URLs" do
    assert_not matcher("https://example.com/feed.xml").match?
  end

  test "#match? should not match URLs that only mention reddit in path" do
    assert_not matcher("https://example.com/reddit.com/r/programming/").match?
  end

  test "#match? should handle blank inputs" do
    assert_not matcher("").match?
    assert_not matcher(nil).match?
  end
end
