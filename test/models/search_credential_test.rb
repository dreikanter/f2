require "test_helper"

class SearchCredentialTest < ActiveSupport::TestCase
  def user
    @user ||= create(:user)
  end

  test "should be valid with a registered provider and an api_key" do
    credential = build(:search_credential, user: user)
    assert credential.valid?, credential.errors.full_messages.inspect
  end

  test "should reject an unknown provider" do
    credential = build(:search_credential, user: user, provider: "made-up")

    refute credential.valid?
    assert_includes credential.errors[:provider], "is not included in the list"
  end

  test "should reject a blank api_key" do
    credential = build(:search_credential, user: user, credential_data: { "api_key" => "" })

    refute credential.valid?
    assert_includes credential.errors[:base], "Enter your API key"
  end

  test "should reject missing credential_data" do
    credential = build(:search_credential, user: user, credential_data: {})

    refute credential.valid?
    assert_includes credential.errors[:base], "Enter your API key"
  end

  test "should enforce display_name uniqueness per user and provider" do
    create(:search_credential, user: user, provider: "serper", display_name: "Work")
    duplicate = build(:search_credential, user: user, provider: "serper", display_name: "Work")

    refute duplicate.valid?
    assert_includes duplicate.errors[:display_name], "has already been taken"
  end

  test "should allow the same display_name across users" do
    create(:search_credential, user: user, display_name: "Work")
    other = build(:search_credential, user: create(:user), display_name: "Work")

    assert other.valid?
  end

  test "should auto-name a new credential when display_name is blank" do
    credential = create(:search_credential, user: user, display_name: nil)

    assert_match(/\ASerper /, credential.display_name)
  end

  test "should encrypt credential_data so the raw column does not contain the API key" do
    credential = create(:search_credential, user: user,
                                            credential_data: { "api_key" => "serper-secret-12345" })

    raw = ActiveRecord::Base.connection.select_value(
      "SELECT credential_data FROM search_credentials WHERE id = #{ActiveRecord::Base.connection.quote(credential.id)}"
    )
    refute_includes raw.to_s, "serper-secret-12345"
    assert_equal "serper-secret-12345", credential.reload.credential_data["api_key"]
  end

  test "#default? should return true for the user's default credential" do
    credential = create(:search_credential, :default, user: user)

    assert credential.default?
  end

  test "#default? should return false when another credential is default" do
    first = create(:search_credential, :default, user: user, display_name: "first")
    second = create(:search_credential, user: user, display_name: "second")

    refute second.default?
    assert first.default?
  end

  test "#make_default! should set the user's default credential" do
    first = create(:search_credential, :default, user: user, display_name: "first")
    second = create(:search_credential, user: user, display_name: "second")

    second.make_default!

    assert_equal second.id, user.reload.default_search_credential_id
    refute first.reload.default?
    assert second.reload.default?
  end

  test "#web_search_provider should resolve the provider with the decrypted key" do
    credential = create(:search_credential, user: user, provider: "brave",
                                            credential_data: { "api_key" => "brave-key" })
    resolved = Object.new
    arguments = nil
    resolver = lambda do |name, api_key:|
      arguments = [name, api_key]
      resolved
    end

    WebSearchProvider.stub(:for, resolver) do
      assert_same resolved, credential.web_search_provider
    end

    assert_equal ["brave", "brave-key"], arguments
  end

  test "state enum should support the managed credential lifecycle" do
    credential = create(:search_credential, user: user)

    assert credential.pending?
    credential.validating!
    assert credential.validating?
    credential.active!
    assert credential.active?
    credential.inactive!
    assert credential.inactive?
  end

  test "#deactivate! should persist the error and create a warning event" do
    credential = create(:search_credential, :active, user: user)

    assert_difference("Event.count", 1) do
      credential.deactivate!(last_error: "Serper: HTTP 401")
    end

    credential.reload
    event = Event.order(:created_at).last
    assert credential.inactive?
    assert_equal "Serper: HTTP 401", credential.last_error
    assert_not_nil credential.last_validated_at
    assert_equal "search_credential_deactivated", event.type
    assert_equal "warning", event.level
    assert_equal credential, event.subject
    assert_equal user, event.user
  end

  test "destroying the default credential should clear the user's default reference" do
    credential = create(:search_credential, :default, user: user)

    credential.destroy!

    assert_nil user.reload.default_search_credential_id
  end

  test "user should expose owned search credentials" do
    credential = create(:search_credential, user: user)

    assert_includes user.search_credentials, credential
  end
end
