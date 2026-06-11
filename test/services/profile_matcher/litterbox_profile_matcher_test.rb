require "test_helper"

class ProfileMatcher::LitterboxProfileMatcherTest < ActiveSupport::TestCase
  def matcher(url)
    ProfileMatcher::LitterboxProfileMatcher.new(url)
  end

  test ".input_shape should be :url" do
    assert_equal :url, ProfileMatcher::LitterboxProfileMatcher.input_shape
  end

  test ".match_specificity should be 100" do
    assert_equal 100, ProfileMatcher::LitterboxProfileMatcher.match_specificity
  end

  test ".depends_on_ai should be false" do
    assert_equal false, ProfileMatcher::LitterboxProfileMatcher.depends_on_ai
  end

  test "#match? should match litterboxcomics.com URLs" do
    assert matcher("https://www.litterboxcomics.com/feed/").match?
  end

  test "#match? should match litterboxcomics.com without subdomain" do
    assert matcher("https://litterboxcomics.com/feed/").match?
  end

  test "#match? should match feeds.feedburner.com URLs with litterboxcomics path" do
    assert matcher("https://feeds.feedburner.com/litterboxcomics/yS3QAzAMEMP").match?
  end

  test "#match? should not match feedburner.com URLs without litterboxcomics path" do
    assert_not matcher("https://feeds.feedburner.com/someotherfeed/abc123").match?
  end

  test "#match? should not match feedburner.com URLs with litterboxcomics not at path start" do
    assert_not matcher("https://feeds.feedburner.com/other/litterboxcomics").match?
  end

  test "#match? should not match feedburner.com URLs with litterboxcomics as path prefix of another feed" do
    assert_not matcher("https://feeds.feedburner.com/litterboxcomicsevil/yS3QAzAMEMP").match?
  end

  test "#match? should not match non-feeds feedburner subdomain" do
    assert_not matcher("https://www.feedburner.com/litterboxcomics/yS3QAzAMEMP").match?
  end

  test "#match? should not match non-litterbox URLs" do
    assert_not matcher("https://example.com/feed.xml").match?
  end

  test "#match? should not match URLs that just contain litterboxcomics in path but wrong domain" do
    assert_not matcher("https://evillitterboxcomics.com/feed/").match?
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
