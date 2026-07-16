require "test_helper"

class CredentialRemovalActivityTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def ai_credential
    @ai_credential ||= create(:ai_credential, :active, user: user)
  end

  def search_credential
    @search_credential ||= create(:search_credential, :active, user: user)
  end

  def enabled_ai_feed
    @enabled_ai_feed ||= create(
      :feed,
      :disabled,
      user: user,
      name: "AI news",
      feed_profile_key: "llm",
      params: { "prompt" => "Ruby news" },
      ai_credential: ai_credential,
      search_credential: search_credential,
      ai_model: "claude-sonnet-4-6"
    ).tap { |feed| feed.update_columns(state: Feed.states[:enabled]) }
  end

  test "AI credential removal is explained in the feed's Recent Activity" do
    feed = enabled_ai_feed
    sign_in_as(user)

    ai_credential.destroy!
    get feed_path(feed)

    assert_response :success
    assert_predicate feed.reload, :disabled?
    assert_nil feed.ai_credential_id
    assert_select "h2", text: "Recent Activity"
    assert_select "[data-key='events.entry'][data-event-type='#{AiCredential::REMOVED_EVENT_TYPE}']" do
      assert_select "[data-key='events.description']", text: /was disabled because its AI credentials were removed/
    end
  end

  test "search credential removal is explained in the feed's Recent Activity" do
    feed = enabled_ai_feed
    sign_in_as(user)

    search_credential.destroy!
    get feed_path(feed)

    assert_response :success
    assert_predicate feed.reload, :disabled?
    assert_nil feed.search_credential_id
    assert_select "h2", text: "Recent Activity"
    assert_select "[data-key='events.entry'][data-event-type='#{SearchCredential::REMOVED_EVENT_TYPE}']" do
      assert_select "[data-key='events.description']", text: /was disabled because its search credentials were removed/
    end
  end
end
