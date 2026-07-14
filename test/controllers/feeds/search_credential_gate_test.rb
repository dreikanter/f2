require "test_helper"

class Feeds::SearchCredentialGateTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  test "create saves a draft and redirects to search credential setup" do
    sign_in_as(user)

    assert_difference("Feed.count", 1) do
      post feeds_path, params: {
        feed: {
          params: { prompt: "Ruby news" },
          name: "Ruby search",
          feed_profile_key: "llm"
        },
        enable_feed: "1",
        commit: "save_as_draft_and_add_search_credentials"
      }
    end

    feed = Feed.last
    assert_predicate feed, :draft?
    assert_redirected_to new_search_credential_path(feed_id: feed.id)
  end
end
