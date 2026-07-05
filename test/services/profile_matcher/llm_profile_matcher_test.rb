require "test_helper"

class ProfileMatcher::LlmProfileMatcherTest < ActiveSupport::TestCase
  def matcher(input)
    ProfileMatcher::LlmProfileMatcher.new(input)
  end

  test ".input_shape should be :any" do
    assert_equal :any, ProfileMatcher::LlmProfileMatcher.input_shape
  end

  test ".match_specificity should be 1" do
    # Lowest specificity so the AI fallback always ranks below the structured
    # matchers (RSS, YouTube, …) for the same input.
    assert_equal 1, ProfileMatcher::LlmProfileMatcher.match_specificity
  end

  test ".depends_on_ai should be true" do
    assert_equal true, ProfileMatcher::LlmProfileMatcher.depends_on_ai
  end

  test "#match? should match a non-blank URL input" do
    assert matcher("https://example.com/page").match?
  end

  test "#match? should match a non-blank free-text query" do
    assert matcher("climate change news").match?
  end

  test "#match? should not match blank or nil input" do
    assert_not matcher("").match?
    assert_not matcher("   ").match?
    assert_not matcher(nil).match?
  end
end
