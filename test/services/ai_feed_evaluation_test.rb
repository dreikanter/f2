require "test_helper"
require Rails.root.join("script/ai_feed_evaluation")

class AiFeedEvaluationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "#run should roll back failed requests without exposing provider errors" do
    credential = create(:ai_credential, :active)
    stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(
      status: 401, body: { error: { message: "secret provider detail", type: "invalid_api_key" } }
    )
    assert_no_difference ["Feed.count", "LlmChat.count", "RubyLLM::ActiveRecord::Usage.count"] do
      assert_no_enqueued_jobs do
        error = assert_raises(Loader::Error) do
          AiFeedEvaluation.run(credential: credential, model: "gpt-5-nano", prompt: "Find one post")
        end
        assert_not_includes error.message, "secret provider detail"
      end
    end
  end

  test "#run should normalize real discovery without publication or retained records" do
    credential = create(:ai_credential, :active, credential_data: { "api_key" => "evaluation-test-key" })
    response = JSON.parse(file_fixture("llm_transcripts/completed.json").read)
    item = {
      body: "A source post",
      source_url: "https://example.com/post",
      title: "",
      supplementary: [],
      images: [],
      published_at: ""
    }
    response["output"].last["content"].first["text"] = { items: [item] }.to_json
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .with(headers: { "Authorization" => "Bearer evaluation-test-key" })
      .to_return_json(body: response)

    assert_no_difference ["Feed.count", "FeedEntry.count", "FeedEntryUid.count", "Post.count", "LlmChat.count", "RubyLLM::ActiveRecord::Usage.count"] do
      assert_no_enqueued_jobs do
        report = AiFeedEvaluation.run(credential: credential, model: "gpt-5-nano", prompt: "Find one source post")
        assert_equal 1, report[:usable_new_posts]
        assert_equal "https://example.com/post", report[:posts].sole.fetch("source_url")
        assert_includes report[:posts].sole.fetch("content"), "A source post"
        assert_not_includes JSON.generate(report), "evaluation-test-key"
      end
    end
    assert_requested request, times: 1
  end
end
