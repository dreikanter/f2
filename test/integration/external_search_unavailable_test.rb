require "test_helper"

class ExternalSearchUnavailableTest < ActionDispatch::IntegrationTest
  test "credential pages should be unavailable" do
    sign_in_as(user)

    get search_credentials_path
    assert_response :not_found

    get new_search_credential_path
    assert_response :not_found

    get search_credential_path(credential)
    assert_response :not_found

    get edit_search_credential_path(credential)
    assert_response :not_found
  end

  test "creating credentials should be unavailable without enqueueing validation" do
    sign_in_as(user)

    assert_no_difference "SearchCredential.count" do
      assert_no_enqueued_jobs do
        post search_credentials_path, params: {
          search_credential: { provider: "serper", credential_data: { api_key: "search-test-key" } }
        }
      end
    end

    assert_response :not_found
  end

  test "updating credentials should preserve their stored values" do
    sign_in_as(user)
    original = credential.attributes

    assert_no_enqueued_jobs do
      patch search_credential_path(credential), params: { search_credential: { display_name: "Changed" } }
    end

    assert_response :not_found
    assert_equal original, credential.reload.attributes
  end

  test "deleting credentials should preserve their records" do
    sign_in_as(user)
    saved = credential

    assert_no_difference "SearchCredential.count" do
      delete search_credential_path(saved)
    end

    assert_response :not_found
  end

  test "changing the default search credential should be unavailable" do
    sign_in_as(user)
    original = create(:search_credential, :default, user: user)

    patch search_credential_default_path(credential)

    assert_response :not_found
    assert_equal original, user.reload.default_search_credential
  end

  test "polling search credential validation should be unavailable" do
    sign_in_as(user)

    get search_credential_validation_path(credential), headers: { "Accept" => "text/vnd.turbo-stream.html" }

    assert_response :not_found
  end

  test "editing a feed should preserve its hidden inactive search selection" do
    sign_in_as(user)
    ai_credential = create(:ai_credential, :active, user: user)
    feed = create(:feed, user: user, feed_profile_key: "llm", params: { prompt: "News" },
                  ai_credential: ai_credential, ai_model: "gpt-5-nano", search_credential: credential)
    credential.update!(active: false)

    patch feed_path(feed), params: { feed: { name: "Updated feed" } }

    assert_redirected_to feed_path(feed)
    assert_equal "Updated feed", feed.reload.name
    assert_equal credential, feed.search_credential
  end

  test "saving a draft should not detour to unavailable search credential setup" do
    sign_in_as(user)

    post feeds_path, params: {
      feed: { name: "News", feed_profile_key: "llm", params: { prompt: "News" } },
      enable_feed: "0",
      commit: "save_as_draft_and_add_search_credentials"
    }

    feed = user.feeds.sole
    assert feed.draft?
    assert_redirected_to feed_path(feed)
  end

  private

  def user
    @user ||= regular_user
  end

  def credential
    @credential ||= create(:search_credential, :active, user: user)
  end
end
