require "test_helper"
require Rails.root.join("script/ai_feed_evaluation")

class AiFeedEvaluationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "#run should seed isolated history and apply refresh date and duplicate filtering" do
    credential = create(:ai_credential, :active)
    history = create(:feed_entry_uid, uid: "https://example.com/imported")
    response = JSON.parse(file_fixture("llm_transcripts/completed.json").read)
    items = %w[imported stale new].map do |name|
      { body: name, source_url: "https://example.com/#{name}", published_at: name == "stale" ? "2000-01-01T00:00:00Z" : "" }
    end
    response["output"].last["content"].first["text"] = { items: items }.to_json
    stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: response)
    assert_no_difference ["Feed.count", "FeedEntryUid.count", "Post.count"] do
      assert_no_enqueued_jobs do
        report = AiFeedEvaluation.run(credential: credential, model: "gpt-5-nano", prompt: "Find posts",
          max_items: 3, imported_urls: [history.uid], import_after: 1.day.ago)
        assert_equal 2, report[:filtered]
        assert_equal 1, report[:usable_new_posts]
        assert_equal "https://example.com/new", report[:posts].sole.fetch("source_url")
      end
    end
    assert_equal "https://example.com/imported", history.reload.uid
  end

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
        assert_equal "openai", report[:provider]
        assert_equal "gpt-5-nano", report[:model]
        assert_equal "Find one source post", report[:configuration].fetch("prompt")
        assert_match(/\A[0-9a-f]{40}\z/, report[:revision])
        assert report[:latency_seconds].positive?
        assert_equal [item.stringify_keys], report[:candidates]
        assert_equal 1, report[:discovered]
        assert_equal 0, report[:filtered]
        assert_equal 0, report[:rejected]
        assert_equal 40, report[:usage].sole.fetch("input_tokens")
        assert_equal "gpt-5-nano", report[:usage].sole.fetch("model")
        assert_equal 1, report[:search_calls]
        assert_equal 1, report[:cost_totals].fetch(:call_count)
        assert_includes report[:tool_cost_usd], "Unknown"
        assert_includes report[:source_verification], "Unavailable"
        assert report[:system_prompt].present?
      end
    end
    assert_requested request, times: 1
  end
end
