require "test_helper"
require Rails.root.join("script/ai_feed_evaluation")

class AiFeedEvaluationCasesTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  YAML.safe_load_file(Rails.root.join("script/ai_feed_cases.yml")).each do |name, scenario|
    test "#run should characterize the current #{name} outcome offline" do
      travel_to Time.utc(2026, 9, 27, 18) do
        credential = create(:ai_credential, :active)
        response = JSON.parse(file_fixture("llm_transcripts/completed.json").read)
        response["output"].select! { |part| part["type"] == "message" } if scenario["search_calls"] == 0
        response["output"].last["content"].first["text"] = { items: scenario.fetch("items") }.to_json
        request = stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: response)
        assert_no_difference ["Feed.count", "FeedEntryUid.count", "LlmChat.count", "Post.count"] do
          assert_no_enqueued_jobs do
            report = AiFeedEvaluation.run(credential: credential, model: "gpt-5-nano", prompt: scenario.fetch("prompt"),
              max_items: scenario.fetch("max_items", 1), imported_urls: scenario.fetch("imported_urls", []),
              import_after: Time.current.beginning_of_day)
            if (path = ENV["AI_EVAL_OFFLINE_REPORT"])
              File.open(path, "a") { |file| file.puts JSON.generate(report.merge(case: name, mode: "offline_fixture")) }
            end
            assert_equal scenario.fetch("expected_usable"), report[:usable_new_posts]
            assert_equal scenario.fetch("expected_rejected", 0), report[:rejected]
            assert_equal scenario.fetch("expected_filtered", 0), report[:filtered]
            assert_equal scenario.fetch("search_calls", 1), report[:search_calls]
            if scenario["expected_content"]
              assert_includes report[:posts].sole.fetch("content"), scenario["expected_content"]
            end
            if scenario["expected_published_at"]
              assert_equal Time.iso8601(scenario["expected_published_at"]), report[:posts].sole.fetch("published_at")
            end
          end
        end
        assert_requested request, times: 1
      end
    end
  end
end
