require "test_helper"

class LlmClient::SearchProviderInjectionTest < ActiveSupport::TestCase
  test "web calls resolve the provider from the active search credential" do
    user = create(:user)
    ai_credential = create(:ai_credential, :active, user: user)
    search_credential = create(:search_credential, :active, user: user)
    provider = Object.new
    context = LlmClient::CallContext.new(
      feed: nil,
      profile_key: "llm",
      stage: :loader,
      model: "claude-sonnet-4-6",
      search_credential: search_credential
    )

    search_credential.stub(:web_search_provider, provider) do
      assert_same provider, LlmClient.new(ai_credential).send(:search_provider_for, context)
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
        client.send(:search_provider_for, context)
      end
    end
  end
end
