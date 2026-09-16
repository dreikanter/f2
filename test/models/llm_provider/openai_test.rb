require "test_helper"
require "socket"

class LlmProvider::OpenaiTest < ActiveSupport::TestCase
  def client
    @client ||= LlmProvider::Openai.new(credential_data: { "api_key" => "first-key" })
  end

  test "#context should bound stalled HTTP requests through the SDK transport" do
    context = client.context
    assert_equal 180, context.config.request_timeout
    server = TCPServer.new("127.0.0.1", 0)
    context.config.openai_api_base = "http://127.0.0.1:#{server.addr[1]}/v1"
    context.config.request_timeout = 0.05
    chat = context.chat(model: "gpt-5-nano", provider: :openai, protocol: client.protocol)
    worker = Thread.new do
      socket = server.accept
      socket.readpartial(16_384)
      sleep 0.2
    ensure
      socket&.close
    end
    WebMock.disable_net_connect!(allow_localhost: true)

    assert_raises(Faraday::TimeoutError) { chat.ask("Find one item.") }
  ensure
    WebMock.disable_net_connect!
    server&.close
    worker&.join
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
