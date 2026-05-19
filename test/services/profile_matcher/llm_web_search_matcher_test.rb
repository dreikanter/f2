require "test_helper"

class ProfileMatcher::LlmWebSearchMatcherTest < ActiveSupport::TestCase
  def matcher(input)
    ProfileMatcher::LlmWebSearchMatcher.new(input)
  end

  test "should declare query input_shape" do
    assert_equal :query, ProfileMatcher::LlmWebSearchMatcher.input_shape
  end

  test "should be flagged as AI-dependent" do
    assert ProfileMatcher::LlmWebSearchMatcher.depends_on_ai
  end

  test "#match? should accept free-text queries" do
    assert matcher("ai safety news").match?
    assert matcher("climate change updates").match?
  end

  test "#match? should reject inputs that are too short" do
    refute matcher("a").match?
    refute matcher("").match?
  end

  test "#match? should reject overly long inputs" do
    refute matcher("x" * 201).match?
  end

  test "should map to the llm_web_search profile key" do
    assert_equal "llm_web_search", ProfileMatcher::LlmWebSearchMatcher.profile_key
  end
end
