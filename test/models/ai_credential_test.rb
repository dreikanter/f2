require "test_helper"

class AiCredentialTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  test "should be valid with a registered provider and an api_key" do
    credential = build(:ai_credential, user: user)
    assert credential.valid?, credential.errors.full_messages.inspect
  end

  test "should reject an unknown provider" do
    credential = build(:ai_credential, user: user, provider: "made-up")
    refute credential.valid?
    assert_includes credential.errors[:provider], "is not included in the list"
  end

  test "should reject a blank api_key" do
    credential = build(:ai_credential, user: user, credential_data: { "api_key" => "" })
    refute credential.valid?
    assert_includes credential.errors[:base], "Enter your API key"
  end

  test "should reject missing credential_data" do
    credential = build(:ai_credential, user: user, credential_data: {})
    refute credential.valid?
    assert_includes credential.errors[:base], "Enter your API key"
  end

  test "should enforce display_name uniqueness per (user, provider)" do
    create(:ai_credential, user: user, provider: "anthropic", display_name: "Work")
    duplicate = build(:ai_credential, user: user, provider: "anthropic", display_name: "Work")

    refute duplicate.valid?
    assert_includes duplicate.errors[:display_name], "has already been taken"
  end

  test "should allow the same display_name across users" do
    create(:ai_credential, user: user, display_name: "Work")
    other = build(:ai_credential, user: create(:user), display_name: "Work")

    assert other.valid?
  end

  test "should encrypt credential_data so the raw column doesn't contain the API key" do
    credential = create(:ai_credential, user: user, credential_data: { "api_key" => "sk-ant-secret-12345" })

    raw = ActiveRecord::Base.connection.select_value(
      "SELECT credential_data FROM ai_credentials WHERE id = #{credential.id}"
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

  test "destroy should be a no-op when no feeds reference the credential" do
    credential = create(:ai_credential, user: user)

    assert_difference("AiCredential.count", -1) do
      credential.destroy!
    end
  end

  test "destroy should nullify dependent feeds and disable any feed left enabled" do
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

  test "#supported_models should keep only models the capability matrix verifies" do
    credential = build(:ai_credential, provider: "anthropic",
                                       available_models: [{ "id" => "claude-sonnet-4-6" }, { "id" => "unverified-model" }])

    assert_equal ["claude-sonnet-4-6"], credential.supported_models.map { |model| model["id"] }
  end

  test "#supported_models should be empty for a provider with no matrix rows" do
    credential = build(:ai_credential, provider: "anthropic",
                                       available_models: [{ "id" => "some-model" }])
    credential.provider = "openrouter"

    assert_empty credential.supported_models
  end

  test "#supports_model? should be true only for a verified model in the snapshot" do
    credential = build(:ai_credential, provider: "anthropic",
                                       available_models: [{ "id" => "claude-sonnet-4-6" }])

    assert credential.supports_model?("claude-sonnet-4-6")
    assert_not credential.supports_model?("some-other-model")
  end

  test "#supports_model? should be false for a snapshot model missing from the matrix" do
    credential = build(:ai_credential, provider: "anthropic",
                                       available_models: [{ "id" => "unverified-model" }])

    assert_not credential.supports_model?("unverified-model")
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

  test "#default_supported_model should resolve a moonshot credential to its verified model" do
    credential = build(:ai_credential, provider: "moonshot",
                                       available_models: [{ "id" => "kimi-k2.5" }])

    assert_equal "kimi-k2.5", credential.default_supported_model
  end

  test "#default_supported_model should be nil when nothing is supported" do
    credential = build(:ai_credential, provider: "anthropic",
                                       available_models: [{ "id" => "unverified-model" }])

    assert_nil credential.default_supported_model
  end
end
