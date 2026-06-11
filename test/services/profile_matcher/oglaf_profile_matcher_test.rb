require "test_helper"

class ProfileMatcher::OglafProfileMatcherTest < ActiveSupport::TestCase
  def matcher(url)
    ProfileMatcher::OglafProfileMatcher.new(url)
  end

  test ".input_shape should be :url" do
    assert_equal :url, ProfileMatcher::OglafProfileMatcher.input_shape
  end

  test ".match_specificity should be 100" do
    # Higher than RSS (10) so oglaf.com URLs prefer the Oglaf profile.
    assert_equal 100, ProfileMatcher::OglafProfileMatcher.match_specificity
  end

  test ".depends_on_ai should be false" do
    assert_equal false, ProfileMatcher::OglafProfileMatcher.depends_on_ai
  end

  test "#match? should match oglaf.com URLs" do
    assert matcher("https://www.oglaf.com/feeds/rss/").match?
  end

  test "#match? should match the bare oglaf.com domain" do
    assert matcher("https://oglaf.com/latest/").match?
  end

  test "#match? should not match non-oglaf URLs" do
    assert_not matcher("https://example.com/feed.xml").match?
  end

  test "#match? should not match URLs that just contain oglaf.com in path" do
    assert_not matcher("https://example.com/oglaf.com/feed.xml").match?
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
