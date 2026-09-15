require "test_helper"

class LlmProvider::OpenaiTest < ActiveSupport::TestCase
  def client
    @client ||= LlmProvider::Openai.new(credential_data: { "api_key" => "first-key" })
  end

  test "#request_options should translate execution limits for Responses" do
    chat = client.context.chat(model: "gpt-5-nano", provider: :openai, protocol: client.protocol)
    chat.with_server_tools(:web_search)
    chat.with_schema(type: "object", properties: { items: { type: "array", items: { type: "string" } } }, required: ["items"], additionalProperties: false)
    chat.with_provider_options(client.request_options(tool_call_limit: 2, output_token_limit: 1_024))
    payload = nil
    request = stub_request(:post, "https://api.openai.com/v1/responses")
      .with(headers: { "Authorization" => "Bearer first-key" })
      .to_return do |http|
        payload = JSON.parse(http.body)
        { body: file_fixture("llm_transcripts/completed.json").read, headers: { "Content-Type" => "application/json" } }
      end

    chat.ask("Find one item.")

    assert_equal "gpt-5-nano", payload.fetch("model")
    assert_equal 2, payload.fetch("max_tool_calls")
    assert_equal 1_024, payload.fetch("max_output_tokens")
    assert_equal "web_search", payload.fetch("tools").sole.fetch("type")
    assert_equal true, payload.dig("text", "format", "strict")
    assert_requested request, times: 1
  end
end
