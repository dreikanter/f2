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
end
