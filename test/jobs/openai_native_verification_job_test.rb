require "test_helper"

class OpenaiNativeVerificationJobTest < ActiveJob::TestCase
  def operator = @operator ||= create(:user, :dev)
  def job = @job ||= OpenaiNativeVerificationJob.new(operator)
  def job_run = @job_run ||= create(:job_run, job_class: job.class.name, job_id: job.job_id)

  def credential
    @credential ||= create(:ai_credential, :active, user: operator, display_name: "OpenaiNativeVerification",
                            credential_data: { "api_key" => "verification-test-key" })
  end

  test "#perform should verify the real loader and processor and produce a copyable report" do
    credential
    response = completed_response
    response["output"].last["content"].first["text"] = {
      items: [{ body: "A release", source_url: "https://example.com/release", title: "", supplementary: [], images: [], published_at: "" }]
    }.to_json
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .with(headers: { "Authorization" => "Bearer verification-test-key" })
      .to_return do |http|
        payload = JSON.parse(http.body)
        assert_equal "gpt-5-mini", payload.fetch("model")
        assert_equal [{ "type" => "web_search" }], payload.fetch("tools")
        assert_equal true, payload.dig("text", "format", "strict")
        assert_equal 10, payload.dig("text", "format", "schema", "properties", "items", "maxItems")
        assert_equal 4, payload.fetch("max_tool_calls")
        assert_equal 16_384, payload.fetch("max_output_tokens")
        { body: response.to_json, headers: { "Content-Type" => "application/json" } }
      end

    assert_no_difference ["Feed.count", "FeedEntry.count", "Post.count", "LlmUsage.count"] do
      run_on_staging
    end

    assert_equal "PASS", report.fetch("result")
    assert_equal 1, report.fetch("item_count")
    assert_equal 1, report.fetch("requests")
    assert_equal 1, report.fetch("completed_searches")
    assert_equal 40, report.fetch("usage").sole.fetch("input_tokens")
    assert report.fetch("checks").values.all?
    chat = LlmChat.find(report.fetch("chat_id"))
    assert chat.succeeded?
    assert_equal credential, chat.ai_credential
    assert_equal operator, chat.user
    assert_equal "preview", chat.purpose
    assert_nil chat.feed
    assert_not_includes report.to_json, "verification-test-key"
    assert_not_includes report.to_json, "A release"
    assert_not_includes report.to_json, OpenaiNativeVerificationJob::PROMPT
    assert_requested request, times: 1
  end

  test "#perform should accept a valid empty result when native search ran" do
    credential
    stub_response(completed_response)

    run_on_staging

    assert_equal "PASS", report.fetch("result")
    assert_equal 0, report.fetch("item_count")
  end

  test "#perform should skip a non-staging run without any inference" do
    credential
    job_run

    job.perform_now

    assert_equal "SKIP", job_run.events.sole.metadata.fetch("result")
    assert_not_requested :any, /./
  end

  test "#perform should not use another user's named credential" do
    create(:ai_credential, :active, display_name: "OpenaiNativeVerification")

    run_on_staging

    assert_equal "SKIP", job_run.events.sole.metadata.fetch("result")
    assert_not_requested :any, /./
  end

  test "#perform should skip an inactive credential" do
    credential.update!(active: false)

    run_on_staging

    assert_equal "SKIP", job_run.events.sole.metadata.fetch("result")
    assert_not_requested :any, /./
  end

  test "#perform should not repeat the request after job redelivery" do
    credential
    request = stub_response(completed_response)
    serialized_job = job.serialize

    run_on_staging
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("staging")) do
      ActiveJob::Base.deserialize(serialized_job).perform_now
    end

    assert_equal 1, job_run.events.where(type: "job.openai_native_verification.completed").count
    assert_requested request, times: 1
  end

  test "#perform should fail verification when the model does not search" do
    credential
    response = completed_response
    response["output"].shift
    stub_response(response)

    run_on_staging

    assert_equal "FAIL", report.fetch("result")
    assert_equal false, report.dig("checks", "native_search")
    assert_equal true, report.dig("checks", "strict_output")
    assert_equal "failed", report.fetch("chat_status")
  end

  test "#perform should reject output that only satisfies the looser processor schema" do
    credential
    response = completed_response
    response["output"].last["content"].first["text"] = '{"items":[{"body":"A post","source_url":null}]}'
    stub_response(response)

    run_on_staging

    assert_equal "FAIL", report.fetch("result")
    assert_equal false, report.dig("checks", "strict_output")
    assert_equal true, report.dig("checks", "processor_output")
  end

  test "#perform should report invalid JSON without exposing response content" do
    credential
    response = completed_response
    response["output"].last["content"].first["text"] = "private response text"
    stub_response(response)

    run_on_staging

    assert_equal "FAIL", report.fetch("result")
    assert_equal "JSON::ParserError", report.fetch("error_class")
    assert_equal "failed", report.fetch("chat_status")
    assert_not_includes report.to_json, "private response text"
  end

  test "#perform should reject incomplete responses and retain usage" do
    credential
    stub_response(completed_response.merge("status" => "incomplete", "incomplete_details" => { "reason" => "max_output_tokens" }))

    run_on_staging

    assert_equal "FAIL", report.fetch("result")
    assert_equal "failed", report.fetch("chat_status")
    assert_equal 20, report.fetch("usage").sole.fetch("output_tokens")
  end

  test "#perform should preserve timeout outcomes and late usage" do
    credential
    freeze_time do
      stub_request(:post, "https://api.openai.com/v1/responses").to_return do
        travel 180.seconds
        { body: completed_response.to_json, headers: { "Content-Type" => "application/json" } }
      end

      run_on_staging
    end

    assert_equal "FAIL", report.fetch("result")
    assert_equal "interrupted", report.fetch("chat_status")
    assert_equal false, report.dig("checks", "completed_before_deadline")
    assert_equal 20, report.fetch("usage").sole.fetch("output_tokens")
  end

  test "#perform should report a provider rejection without retrying or leaking its message" do
    credential
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .to_return_json(status: 429, body: { error: { message: "private provider message", type: "rate_limit_error", code: "rate_limit_exceeded" } })

    run_on_staging

    assert_equal "FAIL", report.fetch("result")
    assert_equal 429, report.fetch("http_status")
    assert_equal "RubyLLM::RateLimitError", report.fetch("error_class")
    assert_equal "rate_limit_exceeded", report.dig("provider_error", "code")
    assert_equal "failed", report.fetch("chat_status")
    assert_not_includes report.to_json, "private provider message"
    assert_requested request, times: 1
  end

  test "#perform should block a second request if the provider asks for a local tool" do
    credential
    response = completed_response
    response["output"] = [{ type: "function_call", call_id: "unexpected_call", name: "unexpected_tool", arguments: "{}" }]
    request = stub_response(response)

    run_on_staging

    assert_equal "FAIL", report.fetch("result")
    assert_equal "LlmExecution::RequestLimitExceeded", report.fetch("error_class")
    assert_equal 1, report.fetch("requests")
    assert_requested request, times: 1
  end

  private

  def run_on_staging
    job_run
    Rails.stub(:env, ActiveSupport::EnvironmentInquirer.new("staging")) { job.perform_now }
  end

  def report
    job_run.events.find_by!(type: "job.openai_native_verification.completed").metadata
  end

  def completed_response
    JSON.parse(file_fixture("llm_transcripts/completed.json").read).merge("model" => "gpt-5-mini")
  end

  def stub_response(response)
    stub_request(:post, "https://api.openai.com/v1/responses").to_return_json(body: response)
  end
end
