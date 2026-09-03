require "test_helper"

class ProfileMatcher::SavagechickensProfileMatcherTest < ActiveSupport::TestCase
  def matcher(url)
    ProfileMatcher::SavagechickensProfileMatcher.new(url)
  end

  test ".match_specificity should be 100" do
    assert_equal 100, ProfileMatcher::SavagechickensProfileMatcher.match_specificity
  end

  test "#match? should match savagechickens.com URLs" do
    assert matcher("https://savagechickens.com/feed").match?
  end

  test "#match? should match www.savagechickens.com URLs" do
    assert matcher("https://www.savagechickens.com/feed").match?
  end

  test "#match? should not match non-savagechickens URLs" do
    assert_not matcher("https://example.com/feed.xml").match?
  end

  test "#match? should not match domains that merely end with savagechickens.com" do
    assert_not matcher("https://notsavagechickens.com/feed").match?
  end

  test "#match? should handle blank inputs" do
    assert_not matcher("").match?
    assert_not matcher(nil).match?
  end
end
