require "test_helper"

class SearchCredentials::FeedDetourTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup { clear_enqueued_jobs }

  def user
    @user ||= create(:user)
  end

  test "new keeps an owned feed detour" do
    sign_in_as(user)
    feed = create(:feed, :draft, user: user)

    get new_search_credential_url(feed_id: feed.id)

    assert_response :success
    assert_select "form[action=?]", search_credentials_path(feed_id: feed.id)
    assert_select "a[href=?]", edit_feed_path(feed), text: "Back to your feed"
  end

  test "new ignores a foreign feed detour" do
    sign_in_as(user)
    foreign = create(:feed, :draft)

    get new_search_credential_url(feed_id: foreign.id)

    assert_response :success
    assert_select "a[href=?]", edit_feed_path(foreign), count: 0
  end

  test "create attaches the credential to an owned feed and preserves the detour" do
    sign_in_as(user)
    feed = create(:feed, :draft, user: user)

    post search_credentials_url(feed_id: feed.id), params: {
      search_credential: {
        provider: "serper",
        display_name: "Feed search key",
        credential_data: { api_key: "serper-#{SecureRandom.hex(16)}" }
      }
    }

    credential = SearchCredential.last
    assert_equal credential.id, feed.reload.search_credential_id
    assert_redirected_to search_credential_path(credential, feed_id: feed.id)
  end

  test "create does not attach to a foreign feed" do
    sign_in_as(user)
    foreign = create(:feed, :draft)

    post search_credentials_url(feed_id: foreign.id), params: {
      search_credential: {
        provider: "serper",
        display_name: "Feed search key",
        credential_data: { api_key: "serper-#{SecureRandom.hex(16)}" }
      }
    }

    assert_nil foreign.reload.search_credential_id
    assert_redirected_to search_credential_path(SearchCredential.last)
  end
end
