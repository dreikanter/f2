require "test_helper"

class LlmCredentialTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  test "should be valid with a registered provider and an api_key" do
    credential = build(:llm_credential, user: user)
    assert credential.valid?, credential.errors.full_messages.inspect
  end

  test "should reject an unknown provider" do
    credential = build(:llm_credential, user: user, provider: "made-up")
    refute credential.valid?
    assert_includes credential.errors[:provider], "is not included in the list"
  end

  test "should reject a blank api_key" do
    credential = build(:llm_credential, user: user, credential_data: { "api_key" => "" })
    refute credential.valid?
    assert_includes credential.errors[:base], "Enter your API key"
  end

  test "should reject missing credential_data" do
    credential = build(:llm_credential, user: user, credential_data: {})
    refute credential.valid?
    assert_includes credential.errors[:base], "Enter your API key"
  end

  test "should enforce display_name uniqueness per (user, provider)" do
    create(:llm_credential, user: user, provider: "anthropic", display_name: "Work")
    duplicate = build(:llm_credential, user: user, provider: "anthropic", display_name: "Work")

    refute duplicate.valid?
    assert_includes duplicate.errors[:display_name], "has already been taken"
  end

  test "should allow the same display_name across users" do
    create(:llm_credential, user: user, display_name: "Work")
    other = build(:llm_credential, user: create(:user), display_name: "Work")

    assert other.valid?
  end

  test "should encrypt credential_data so the raw column doesn't contain the API key" do
    credential = create(:llm_credential, user: user, credential_data: { "api_key" => "sk-ant-secret-12345" })

    raw = ActiveRecord::Base.connection.select_value(
      "SELECT credential_data FROM llm_credentials WHERE id = #{credential.id}"
    )
    refute_includes raw.to_s, "sk-ant-secret-12345"
    assert_equal "sk-ant-secret-12345", credential.reload.credential_data["api_key"]
  end

  test "should un-default sibling credentials when promoting to default" do
    first = create(:llm_credential, :default, user: user, provider: "anthropic", display_name: "first")
    second = create(:llm_credential, user: user, provider: "anthropic", display_name: "second")

    second.update!(is_default: true)

    assert second.reload.is_default?
    refute first.reload.is_default?
  end

  test "the partial unique index should reject two defaults for the same (user, provider)" do
    create(:llm_credential, :default, user: user, provider: "anthropic", display_name: "first")

    assert_raises(ActiveRecord::RecordNotUnique) do
      # Bypass the `before_save` un-default callback so we can observe the
      # index doing its job as the last-line guard.
      LlmCredential.connection.execute(<<~SQL)
        INSERT INTO llm_credentials (user_id, provider, display_name, credential_data, is_default, state, created_at, updated_at)
        VALUES (#{user.id}, 'anthropic', 'second', '{}', TRUE, 0, NOW(), NOW())
      SQL
    end
  end

  test "should allow defaults in different providers for the same user" do
    skip "no second provider registered yet" unless LlmProvider.all.size > 1

    second_provider = (LlmProvider.names - ["anthropic"]).first
    anthropic = create(:llm_credential, :default, user: user, provider: "anthropic", display_name: "Anthropic default")
    other = create(:llm_credential, :default, user: user, provider: second_provider, display_name: "Other default")

    assert anthropic.reload.is_default?
    assert other.reload.is_default?
  end

  test "#make_default! should atomically promote one credential and un-default siblings" do
    first = create(:llm_credential, :default, user: user, provider: "anthropic", display_name: "first")
    second = create(:llm_credential, user: user, provider: "anthropic", display_name: "second")

    second.make_default!

    assert second.reload.is_default?
    refute first.reload.is_default?
  end

  test "destroy should be a no-op when no feeds reference the credential" do
    credential = create(:llm_credential, user: user)

    assert_difference("LlmCredential.count", -1) do
      credential.destroy!
    end
  end

  test "destroy should nullify dependent feeds and disable any feed left enabled" do
    credential = create(:llm_credential, user: user)
    feed = create(:feed,
                  user: user,
                  llm_credential: credential,
                  state: :disabled,
                  feed_profile_key: "rss",
                  params: { "url" => "http://example.com/feed.xml" })
    enabled_feed = create(:feed,
                          user: user,
                          llm_credential: credential,
                          state: :disabled,
                          feed_profile_key: "rss",
                          params: { "url" => "http://example.com/other.xml" })
    enabled_feed.update_columns(state: Feed.states[:enabled])

    credential.destroy!

    assert_nil feed.reload.llm_credential_id
    assert_nil enabled_feed.reload.llm_credential_id
    assert_equal "disabled", enabled_feed.reload.state
  end
end
