require "test_helper"

class ProfileMatcher::ElementyProfileMatcherTest < ActiveSupport::TestCase
  def matcher(url)
    ProfileMatcher::ElementyProfileMatcher.new(url)
  end

  test ".input_shape should be :url" do
    assert_equal :url, ProfileMatcher::ElementyProfileMatcher.input_shape
  end

  test ".match_specificity should be 100" do
    assert_equal 100, ProfileMatcher::ElementyProfileMatcher.match_specificity
  end

  test ".depends_on_ai should be false" do
    assert_equal false, ProfileMatcher::ElementyProfileMatcher.depends_on_ai
  end

  test "#match? should match bare elementy.ru URLs" do
    assert matcher("https://elementy.ru/rss/news").match?
    assert matcher("https://elementy.ru/novosti_nauki/434641").match?
  end

  test "#match? should match www.elementy.ru URLs" do
    assert matcher("https://www.elementy.ru/rss/news").match?
  end

  test "#match? should not match arbitrary subdomains of elementy.ru" do
    assert_not matcher("https://blog.elementy.ru/feed").match?
  end

  test "#match? should not match non-elementy URLs" do
    assert_not matcher("https://example.com/feed.xml").match?
  end

  test "#match? should not match URLs that just contain elementy.ru in path" do
    assert_not matcher("https://example.com/elementy.ru/feed").match?
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
