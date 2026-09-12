require "test_helper"

class AiCredentialTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  test "#valid? should return true with a registered provider and an api_key" do
    credential = build(:ai_credential, user: user)
    assert credential.valid?, credential.errors.full_messages.inspect
  end

  test "#valid? should reject an unknown provider" do
    credential = build(:ai_credential, user: user, provider: "made-up")
    refute credential.valid?
    assert_includes credential.errors[:provider], "is not included in the list"
  end

  test "#valid? should reject a blank api_key" do
    credential = build(:ai_credential, user: user, credential_data: { "api_key" => "" })
    refute credential.valid?
    assert_includes credential.errors[:base], "Enter your API key"
  end

  test "#valid? should reject missing credential_data" do
    credential = build(:ai_credential, user: user, credential_data: {})
    refute credential.valid?
    assert_includes credential.errors[:base], "Enter your API key"
  end

  test "#valid? should enforce display_name uniqueness per (user, provider)" do
    create(:ai_credential, user: user, provider: "anthropic", display_name: "Work")
    duplicate = build(:ai_credential, user: user, provider: "anthropic", display_name: "Work")

    refute duplicate.valid?
    assert_includes duplicate.errors[:display_name], "has already been taken"
  end

  test "#valid? should allow the same display_name across users" do
    create(:ai_credential, user: user, display_name: "Work")
    other = build(:ai_credential, user: create(:user), display_name: "Work")

    assert other.valid?
  end

  test "#save! should encrypt credential_data so the raw column doesn't contain the API key" do
    credential = create(:ai_credential, user: user, credential_data: { "api_key" => "sk-ant-secret-12345" })

    raw = ActiveRecord::Base.connection.select_value(
      "SELECT credential_data FROM ai_credentials WHERE id = #{ActiveRecord::Base.connection.quote(credential.id)}"
    )
    refute_includes raw.to_s, "sk-ant-secret-12345"
    assert_equal "sk-ant-secret-12345", credential.reload.credential_data["api_key"]
  end

  test "#default? should return true for the user's default credential" do
    credential = create(:ai_credential, :default, user: user)
    assert credential.default?
  end

  test "#default? should return false when another credential is default" do
    first = create(:ai_credential, :default, user: user, display_name: "first")
    second = create(:ai_credential, user: user, display_name: "second")

    refute second.default?
    assert first.default?
  end

  test "#make_default! should set the user's default credential" do
    first = create(:ai_credential, :default, user: user, display_name: "first")
    second = create(:ai_credential, user: user, display_name: "second")

    second.make_default!

    assert_equal second.id, user.reload.default_ai_credential_id
    refute first.reload.default?
    assert second.reload.default?
  end

  test "#make_default! should work when no default exists yet" do
    credential = create(:ai_credential, user: user)
    credential.make_default!
    assert_equal credential.id, user.reload.default_ai_credential_id
  end

  test "#llm_provider should return the registry entry for the provider attribute" do
    credential = create(:ai_credential, user: user, provider: "anthropic")
    assert_equal LlmProvider.find("anthropic"), credential.llm_provider
  end

  test "#can_refresh_models? should require an active credential with an implementation" do
    credential = build(:ai_credential, :active, provider: "openai")
    assert credential.can_refresh_models?

    credential.state = :inactive
    assert_not credential.can_refresh_models?
  end

  test "#can_refresh_models? should keep saved unsupported credentials unavailable" do
    credential = build(:ai_credential, :active, provider: "anthropic")

    assert_not credential.provider_available?
    assert_not credential.can_refresh_models?
    assert_equal "Anthropic", credential.provider_name
  end

  test "#ruby_llm_context should reject an unavailable provider without network calls" do
    credential = build(:ai_credential, :active, provider: "anthropic")

    assert_raises(AiModelCatalog::Unavailable) { credential.ruby_llm_context }
    assert_not_requested :any, /./
  end

  test "#ruby_llm_context should isolate credentials and disable SDK retries" do
    first = build(:ai_credential, provider: "openai", credential_data: { "api_key" => "first-key" })
    second = build(:ai_credential, provider: "openai", credential_data: { "api_key" => "second-key" })
    original_key = RubyLLM.config.openai_api_key

    first_context = first.ruby_llm_context
    second_context = second.ruby_llm_context

    assert_equal "first-key", first_context.config.openai_api_key
    assert_equal "second-key", second_context.config.openai_api_key
    assert_equal 0, first_context.config.max_retries
    assert_equal original_key, RubyLLM.config.openai_api_key
    assert_not_requested :any, /./
  end

  test "#destroy! should remove a credential with no dependent feeds" do
    credential = create(:ai_credential, user: user)

    assert_difference("AiCredential.count", -1) do
      credential.destroy!
    end
  end

  test "#destroy! should nullify dependent feeds and disable any feed left enabled" do
    credential = create(:ai_credential, user: user)
    feed = create(:feed,
                  user: user,
                  ai_credential: credential,
                  state: :disabled,
                  feed_profile_key: "rss",
                  params: { "url" => "http://example.com/feed.xml" })
    enabled_feed = create(:feed,
                          user: user,
                          ai_credential: credential,
                          state: :disabled,
                          feed_profile_key: "rss",
                          params: { "url" => "http://example.com/other.xml" })
    enabled_feed.update_columns(state: Feed.states[:enabled])

    credential.destroy!

    assert_nil feed.reload.ai_credential_id
    assert_nil enabled_feed.reload.ai_credential_id
    assert_equal "disabled", enabled_feed.reload.state
  end

  test "#supported_models should offer listed models without qualification" do
    credential = build(:ai_credential, provider: "anthropic",
                                       available_models: [{ "id" => "claude-sonnet-4-6" }, { "id" => "unverified-model" }])

    assert_equal ["claude-sonnet-4-6", "unverified-model"], credential.supported_models.map { |model| model["id"] }
  end

  test "#supported_models should offer models from every configured provider" do
    credential = build(:ai_credential, provider: "anthropic",
                                       available_models: [{ "id" => "some-model" }])
    credential.provider = "openrouter"

    assert_equal ["some-model"], credential.supported_models.pluck("id")
  end

  test "#supports_model? should be true only for a model in the snapshot" do
    credential = build(:ai_credential, provider: "anthropic",
                                       available_models: [{ "id" => "claude-sonnet-4-6" }])

    assert credential.supports_model?("claude-sonnet-4-6")
    assert_not credential.supports_model?("some-other-model")
  end

  test "#supports_model? should be true for a newly listed model" do
    credential = build(:ai_credential, provider: "anthropic",
                                       available_models: [{ "id" => "unverified-model" }])

    assert credential.supports_model?("unverified-model")
  end

  test "#supports_model? should be false for a blank model id" do
    credential = build(:ai_credential, available_models: [{ "id" => "claude-sonnet-4-6" }])

    assert_not credential.supports_model?(nil)
    assert_not credential.supports_model?("")
  end

  test "#default_supported_model should prefer the provider default when supported" do
    credential = build(:ai_credential, provider: "anthropic",
                                       available_models: [{ "id" => "claude-sonnet-4-6" }])

    assert_equal "claude-sonnet-4-6", credential.default_supported_model
  end

  test "#default_supported_model should resolve a moonshot credential to its listed model" do
    credential = build(:ai_credential, provider: "moonshot",
                                       available_models: [{ "id" => "kimi-k2.6" }])

    assert_equal "kimi-k2.6", credential.default_supported_model
  end

  test "#default_supported_model should choose the first listed model when the default is absent" do
    credential = build(:ai_credential, provider: "anthropic",
                                       available_models: [{ "id" => "unverified-model" }])

    assert_equal "unverified-model", credential.default_supported_model
  end

  test "#deactivate! should persist the error and create a warning event" do
    credential = create(:ai_credential, :active, user: user)

    assert_difference("Event.count", 1) do
      credential.deactivate!(last_error: "Anthropic: HTTP 401")
    end

    credential.reload
    event = Event.order(:created_at).last
    assert credential.inactive?
    assert_equal "Anthropic: HTTP 401", credential.last_error
    assert_not_nil credential.last_validated_at
    assert_equal "ai_credential_deactivated", event.type
    assert_equal "warning", event.level
    assert_equal credential, event.subject
    assert_equal user, event.user
  end

  test "#deactivate! should disable feeds running on the credential" do
    credential = create(:ai_credential, :active, user: user)
    enabled = create(:feed, :enabled, user: user, ai_credential: credential)
    draft = create(:feed, :draft, user: user, ai_credential: credential)

    credential.deactivate!

    assert enabled.reload.disabled?
    assert draft.reload.draft?
  end
  test "#supported_models should exclude known non-text models while leaving unknown metadata selectable" do
    credential = build(:ai_credential, available_models: [
      { "id" => "image", "metadata" => { "output_modalities" => ["image"] } },
      { "id" => "text", "metadata" => { "output_modalities" => ["text", "audio"] } },
      { "id" => "unknown", "capabilities" => [] }
    ])
    assert_equal ["text", "unknown"], credential.supported_models.pluck("id")
  end

  test "#supported_models should use task metadata even when specialized models advertise text output" do
    models = {
      "text-embedding-3-small" => "embedding", "gpt-image-1.5" => "image_generation",
      "gpt-realtime-2.1" => "realtime", "new-transcriber" => "audio_transcription",
      "new-speaker" => "audio_speech", "new-video" => "video_generation", "legacy-model" => "completion"
    }.map do |id, mode|
      { "id" => id, "metadata" => { "task" => { "mode" => mode }, "output_modalities" => ["text", "image", "audio"] } }
    end
    models += [
      { "id" => "chat", "metadata" => { "task" => { "mode" => "chat" }, "tool_call" => false, "structured_output" => false } },
      { "id" => "responses", "metadata" => { "task" => { "mode" => "responses" } } },
      { "id" => "future", "metadata" => { "task" => { "mode" => "future_task" } } },
      { "id" => "unknown" }, { "id" => "text-embedding-unclassified" }
    ]
    credential = build(:ai_credential, available_models: models)

    assert_equal %w[chat responses future unknown text-embedding-unclassified], credential.supported_models.pluck("id")
    assert_equal "chat", credential.default_supported_model
    assert_equal models, credential.available_models
    assert_not_requested :any, /./
  end
end
