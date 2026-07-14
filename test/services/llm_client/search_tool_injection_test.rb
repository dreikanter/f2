require "test_helper"

class LlmClient::SearchToolInjectionTest < ActiveSupport::TestCase
  test "web calls build the search tool from the active search credential with attribution context" do
    user = create(:user)
    ai_credential = create(:ai_credential, :active, user: user)
    search_credential = create(:search_credential, :active, user: user)
    feed = create(:feed, user: user)
    provider = Object.new
    context = LlmClient::CallContext.new(
      feed: feed,
      profile_key: "llm",
      stage: :loader,
      model: "claude-sonnet-4-6",
      purpose: :preview,
      search_credential: search_credential
    )

    search_credential.stub(:web_search_provider, provider) do
      tool = LlmClient.new(ai_credential).send(:search_tool_for, context)

      assert_instance_of LlmClient::Tools::WebSearch, tool
      assert_same provider, tool.instance_variable_get(:@provider)
      assert_same search_credential, tool.instance_variable_get(:@credential)
      assert_same feed, tool.instance_variable_get(:@feed)
      assert_equal :preview, tool.instance_variable_get(:@purpose)
    end
  end

  test "web calls reject a missing or inactive search credential" do
    user = create(:user)
    ai_credential = create(:ai_credential, :active, user: user)
    inactive = create(:search_credential, :inactive, user: user)
    client = LlmClient.new(ai_credential)

    [nil, inactive].each do |search_credential|
      context = LlmClient::CallContext.new(
        feed: nil,
        profile_key: "llm",
        stage: :loader,
        model: "claude-sonnet-4-6",
        search_credential: search_credential
      )

      assert_raises(LlmClient::CredentialMissing) do
        client.send(:search_tool_for, context)
      end
    end
  end
end
