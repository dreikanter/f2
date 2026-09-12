require "test_helper"

class Loader::LlmLoaderTest < ActiveSupport::TestCase
  test "#load should reject AI extraction without inference or usage" do
    feed = build(:feed, feed_profile_key: "llm", params: { "prompt" => "A daily roundup" })

    assert_no_difference -> { LlmUsage.count } do
      error = assert_raises(Loader::Error) { feed.loader_instance.load }
      assert_equal Loader::LlmLoader::UNAVAILABLE_MESSAGE, error.message
    end
    assert_not_requested :any, /./
  end
end
