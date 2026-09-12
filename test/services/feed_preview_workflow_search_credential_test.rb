require "test_helper"

class FeedPreviewWorkflowSearchCredentialTest < ActiveSupport::TestCase
  AI_RUN_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"

  test "#execute should pass the persisted search credential to the temporary feed" do
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
      search_credential: search_credential,
      status: :pending,
      run_id: AI_RUN_ID
    )

    captured_feed = nil
    loader = Struct.new(:load).new([])
    Loader::LlmLoader.stub(:new, lambda { |feed, **_options|
      captured_feed = feed
      loader
    }) do
      FeedPreviewWorkflow.new(preview, run_id: AI_RUN_ID).execute
    end

    assert_equal search_credential, captured_feed.search_credential
    assert_not captured_feed.persisted?
  end
end
