require "test_helper"

class Loader::LlmLoaderSearchCredentialTest < ActiveSupport::TestCase
  test "scheduled AI load carries the feed search credential in the call context" do
    user = create(:user)
    ai_credential = create(:ai_credential, :active, user: user)
    search_credential = create(:search_credential, :active, user: user)
    feed = create(
      :feed,
      user: user,
      feed_profile_key: "llm",
      params: { "prompt" => "ruby releases" },
      ai_credential: ai_credential,
      search_credential: search_credential
    )
    captured_context = nil
    fake_client = Class.new do
      attr_reader :credential

      def initialize(credential, callback)
        @credential = credential
        @callback = callback
      end

      def call(context, **_options)
        @callback.call(context)
        LlmClient::Result.new(payload: { "items" => [] }, usage_id: 1)
      end
    end.new(ai_credential, ->(context) { captured_context = context })

    Loader::LlmLoader.new(feed, llm_client: fake_client).load

    assert_same search_credential, captured_context.search_credential
    assert_same feed, captured_context.feed
    assert_equal :scheduled_run, captured_context.purpose
  end
end
