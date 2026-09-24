require "test_helper"

class LlmProvider::XaiTest < ActiveSupport::TestCase
  test "#context should isolate credentials and bound the SDK transport" do
    data = { "api_key" => "first-key" }
    provider = LlmProvider::Xai.new(credential_data: data)
    data["api_key"] = "replacement-key"
    original_key = RubyLLM.config.xai_api_key

    context = provider.context

    assert_equal "first-key", context.config.xai_api_key
    assert_equal 180, context.config.request_timeout
    assert_equal 0, context.config.max_retries
    assert_equal original_key, RubyLLM.config.xai_api_key
  end

  test "#request_options should bound xAI turns and expose both retrieval tools through the SDK" do
    provider = LlmProvider::Xai.new(credential_data: { "api_key" => "xai-test-key" })
    chat = provider.context.chat(model: "grok-4.3", provider: :xai, protocol: provider.protocol)
    chat.with_provider_tools(*provider.retrieval_tools)
    chat.with_provider_options(provider.request_options(tool_call_limit: 2, output_token_limit: 1_024))
    payload = nil
    response = JSON.parse(file_fixture("llm_transcripts/completed.json").read)
    response["model"] = "grok-4.3"
    request = stub_request(:post, "https://api.x.ai/v1/responses")
      .with(headers: { "Authorization" => "Bearer xai-test-key" })
      .to_return do |http|
        payload = JSON.parse(http.body)
        { body: response.to_json, headers: { "Content-Type" => "application/json" } }
      end

    result = chat.ask("Find one AI news post.")

    assert_equal "grok-4.3", payload.fetch("model")
    assert_equal %w[web_search x_search], payload.fetch("tools").pluck("type")
    assert_equal 2, payload.fetch("max_turns")
    assert_equal false, payload.fetch("parallel_tool_calls")
    assert_equal 1_024, payload.fetch("max_output_tokens")
    assert_not payload.key?("max_tool_calls")
    assert_equal '{"items":[]}', result.content
    assert_requested request, times: 1
  end
end
