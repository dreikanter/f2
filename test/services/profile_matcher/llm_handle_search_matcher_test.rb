require "test_helper"

class ProfileMatcher::LlmHandleSearchMatcherTest < ActiveSupport::TestCase
  def matcher(input)
    ProfileMatcher::LlmHandleSearchMatcher.new(input)
  end

  test "should declare handle input_shape" do
    assert_equal :handle, ProfileMatcher::LlmHandleSearchMatcher.input_shape
  end

  test "should be flagged as AI-dependent" do
    assert ProfileMatcher::LlmHandleSearchMatcher.depends_on_ai
  end

  test "#match? should accept plain @handle" do
    assert matcher("@johndoe").match?
  end

  test "#match? should accept fediverse-style handles" do
    assert matcher("@user@example.social").match?
  end

  test "#match? should reject URLs and free text" do
    refute matcher("https://example.com").match?
    refute matcher("plain text").match?
    refute matcher("").match?
  end

  test "should map to the llm_handle_search profile key" do
    assert_equal "llm_handle_search", ProfileMatcher::LlmHandleSearchMatcher.profile_key
  end
end
