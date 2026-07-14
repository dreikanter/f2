require "test_helper"

class FeedPreviewWorkflowSearchCredentialTest < ActiveSupport::TestCase
  test "AI preview passes its explicit search credential to the temporary feed and LLM context" do
    user = create(:user)
    ai_credential = create(
      :ai_credential,
      :active,
      user: user,
      available_models: [{ "id" => "claude-sonnet-4-6" }]
    )
    search_credential = create(:search_credential, :active, user: user)
    preview = create(
      :feed_preview,
      user: user,
      feed_profile_key: "llm",
      params: { "prompt" => "rust async" },
      ai_credential: ai_credential,
      ai_model: "claude-sonnet-4-6",
      status: :pending,
      run_id: "run-ai"
    )

    captured_feed = nil
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
    end

    LlmClient.stub(:for, lambda { |feed|
      captured_feed = feed
      fake_client.new(ai_credential, ->(context) { captured_context = context })
    }) do
      FeedPreviewWorkflow.new(
        preview,
        run_id: "run-ai",
        search_credential: search_credential
      ).execute
    end

    assert_same search_credential, captured_feed.search_credential
    assert_same search_credential, captured_context.search_credential
    assert_not captured_feed.persisted?
  end
end
