require "test_helper"

class ProfileMatcher::SmbcProfileMatcherTest < ActiveSupport::TestCase
  def matcher(url)
    ProfileMatcher::SmbcProfileMatcher.new(url)
  end

  test ".match_specificity should be 100" do
    # Higher than RSS (10) so smbc-comics.com URLs prefer the SMBC profile.
    assert_equal 100, ProfileMatcher::SmbcProfileMatcher.match_specificity
  end

  test "#match? should match smbc-comics.com URLs" do
    assert matcher("https://www.smbc-comics.com/comic/rss").match?
  end

  test "#match? should match the bare smbc-comics.com host" do
    assert matcher("https://smbc-comics.com/").match?
  end

  test "#match? should not match non-SMBC URLs" do
    assert_not matcher("https://example.com/feed.xml").match?
  end

  test "#match? should not match arbitrary smbc-comics.com subdomains" do
    assert_not matcher("https://blog.smbc-comics.com/feed").match?
  end

  test "#match? should not match URLs that just contain smbc-comics.com in path" do
    assert_not matcher("https://example.com/smbc-comics.com/feed.xml").match?
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
