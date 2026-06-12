require "test_helper"

class ProfileMatcher::BuniProfileMatcherTest < ActiveSupport::TestCase
  def matcher(url)
    ProfileMatcher::BuniProfileMatcher.new(url)
  end

  test ".input_shape should be :url" do
    assert_equal :url, ProfileMatcher::BuniProfileMatcher.input_shape
  end

  test ".match_specificity should be 100" do
    # Higher than RSS (10) so bunicomic.com URLs prefer the Buni profile.
    assert_equal 100, ProfileMatcher::BuniProfileMatcher.match_specificity
  end

  test ".depends_on_ai should be false" do
    assert_equal false, ProfileMatcher::BuniProfileMatcher.depends_on_ai
  end

  test "#match? should match bunicomic.com URLs" do
    assert matcher("http://bunicomic.com/feed/").match?
  end

  test "#match? should match the www feed URL" do
    assert matcher("https://www.bunicomic.com/feed/").match?
  end

  test "#match? should not match non-buni URLs" do
    assert_not matcher("https://example.com/feed.xml").match?
  end

  test "#match? should not match arbitrary subdomains" do
    assert_not matcher("https://comics.bunicomic.com/feed/").match?
  end

  test "#match? should not match URLs that just contain bunicomic.com in path" do
    assert_not matcher("https://example.com/bunicomic.com/feed.xml").match?
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
