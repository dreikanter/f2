require "test_helper"
require Rails.root.join("script/ai_feed_evaluation")

class AiFeedEvaluationTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "#runner should invoke exactly one named case and emit JSON" do
    credential = create(:ai_credential, :active)
    settings = { "AI_EVAL_CREDENTIAL_ID" => credential.id, "AI_EVAL_MODEL" => "gpt-5-nano", "AI_EVAL_CASE" => "seeded" }
    fetch = ENV.method(:fetch)
    calls = []
    AiFeedEvaluation.stub(:run, ->(**args) { calls << args; {} }) do
      ENV.stub(:fetch, ->(key, *defaults) { settings.fetch(key) { fetch.call(key, *defaults) } }) do
        output = capture_io { load Rails.root.join("script/evaluate_ai_feed.rb") }.first
        assert_equal({ "mode" => "live", "case" => "seeded", "case_count" => 1, "repetitions" => 1 }, JSON.parse(output))
      end
    end
    assert_equal credential, calls.sole.fetch(:credential)
    assert_equal ["https://x.com/dhh/status/2104203632572842293"], calls.sole.fetch(:imported_urls)
  end

  test "#runner should reject unknown cases before discovery with safe output" do
    capture_error_reports do
      ENV.stub(:fetch, "unknown-secret-case") do
        output = capture_io { assert_raises(SystemExit) { load Rails.root.join("script/evaluate_ai_feed.rb") } }.last
        assert_equal({ "error" => "KeyError" }, JSON.parse(output))
      end
    end
  end

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
        errors = capture_error_reports do
          report = AiFeedEvaluation.run(credential: credential, model: "gpt-5-nano", prompt: "Find one post")
          assert_equal "Loader::Error", report[:error]
          assert_equal 0, report[:usable_new_posts]
          assert_nil report[:discovered]
          assert_equal "failed", report[:usage].sole.fetch("status")
          assert_not_includes JSON.generate(report), "secret provider detail"
        end
        assert_instance_of Loader::Error, errors.sole.error
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
