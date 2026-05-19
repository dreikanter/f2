require "test_helper"

class ProfileMatcher::LlmWebsiteExtractorMatcherTest < ActiveSupport::TestCase
  def matcher(input, body = nil)
    ProfileMatcher::LlmWebsiteExtractorMatcher.new(input, body)
  end

  test "should declare url input_shape" do
    assert_equal :url, ProfileMatcher::LlmWebsiteExtractorMatcher.input_shape
  end

  test "should declare the lowest specificity so it always ranks below structured matchers" do
    assert_equal 1, ProfileMatcher::LlmWebsiteExtractorMatcher.match_specificity
    assert_operator ProfileMatcher::LlmWebsiteExtractorMatcher.match_specificity, :<, ProfileMatcher::RssProfileMatcher.match_specificity
    assert_operator ProfileMatcher::LlmWebsiteExtractorMatcher.match_specificity, :<, ProfileMatcher::XkcdProfileMatcher.match_specificity
  end

  test "should be flagged as AI-dependent" do
    assert ProfileMatcher::LlmWebsiteExtractorMatcher.depends_on_ai
  end

  test "#match? should return true for any HTTP URL" do
    assert matcher("http://example.com").match?
    assert matcher("https://example.com/page").match?
    assert matcher("https://sub.example.com/path?q=1").match?
  end

  test "#match? should return false for blank input" do
    refute matcher(nil).match?
    refute matcher("").match?
  end

  test "#match? should return false for non-HTTP inputs" do
    refute matcher("just text").match?
    refute matcher("@handle").match?
  end
end
