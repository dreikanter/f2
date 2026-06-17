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
end
