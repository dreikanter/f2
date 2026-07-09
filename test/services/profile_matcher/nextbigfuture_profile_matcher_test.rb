require "test_helper"

class ProfileMatcher::NextbigfutureProfileMatcherTest < ActiveSupport::TestCase
  def matcher(url)
    ProfileMatcher::NextbigfutureProfileMatcher.new(url)
  end

  test ".match_specificity should be 100" do
    # Higher than RSS (10) so nextbigfuture.com URLs prefer the Next Big Future profile.
    assert_equal 100, ProfileMatcher::NextbigfutureProfileMatcher.match_specificity
  end

  test "#match? should match nextbigfuture.com URLs" do
    assert matcher("https://www.nextbigfuture.com/feed").match?
  end

  test "#match? should match nextbigfuture.com subdomains" do
    assert matcher("https://nextbigfuture.com/feed").match?
  end

  test "#match? should not match non-nextbigfuture URLs" do
    assert_not matcher("https://example.com/feed.xml").match?
  end

  test "#match? should not match URLs that just contain nextbigfuture in path" do
    assert_not matcher("https://example.com/nextbigfuture.com/feed").match?
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
