require "test_helper"

class LlmProviderTest < ActiveSupport::TestCase
  test "#all should offer implemented providers" do
    assert_equal ["openai"], LlmProvider.names
    assert_equal({ "openai" => LlmProvider.find("openai") }, LlmProvider.all)
  end

  test "#find should return the OpenAI configuration" do
    config = LlmProvider.find(:openai)

    assert_equal LlmProvider::Openai, config.fetch(:client_class)
    assert_equal "OpenAI", config.fetch(:display_name)
    assert_equal "gpt-5.6-luna", config.fetch(:default_model)
  end

  test "#find should reject unknown providers" do
    assert_raises(KeyError) { LlmProvider.find("does-not-exist") }
    assert_raises(KeyError) { LlmProvider.find(nil) }
  end

  test ".web_search_call_count should use the recorded provider without credentials" do
    calls = [{ "type" => "web_search_call", "id" => "search_1" }]

    assert_equal 1, LlmProvider.web_search_call_count(provider: "openai", calls: calls)
    assert_nil LlmProvider.web_search_call_count(provider: "removed-provider", calls: calls)
  end

  test ".web_search_call_count should leave interpretation to each provider" do
    calls = [{ "type" => "web_search_call", "id" => "search_1" }]

    assert_nil LlmProvider::Base.web_search_call_count(calls)
  end
end
