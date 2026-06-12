require "test_helper"

class ProfileMatcher::LobstersProfileMatcherTest < ActiveSupport::TestCase
  def matcher(url)
    ProfileMatcher::LobstersProfileMatcher.new(url)
  end

  test ".input_shape should be :url" do
    assert_equal :url, ProfileMatcher::LobstersProfileMatcher.input_shape
  end

  test ".match_specificity should be 100" do
    # Higher than RSS (10) so lobste.rs URLs prefer the Lobsters profile.
    assert_equal 100, ProfileMatcher::LobstersProfileMatcher.match_specificity
  end

  test ".depends_on_ai should be false" do
    assert_equal false, ProfileMatcher::LobstersProfileMatcher.depends_on_ai
  end

  test "#match? should match lobste.rs URLs" do
    assert matcher("https://lobste.rs/t/sample.rss").match?
  end

  test "#match? should match the lobste.rs front page feed" do
    assert matcher("https://lobste.rs/rss").match?
  end

  test "#match? should not match non-lobsters URLs" do
    assert_not matcher("https://example.com/feed.xml").match?
  end

  test "#match? should not match URLs that just contain lobste.rs in path" do
    assert_not matcher("https://example.com/lobste.rs/feed.xml").match?
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
