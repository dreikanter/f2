require "test_helper"

class Feeds::WebhookTokensControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, :webhook, user: user)
  end

  def endpoint
    @endpoint ||= create(:webhook_endpoint, feed: feed)
  end

  test "#update should replace the token" do
    sign_in_as(user)
    old_token = endpoint.encrypted_token

    patch feed_webhook_token_path(feed)

    assert_redirected_to feed_path(feed)
    assert_not_equal old_token, endpoint.reload.encrypted_token
  end

  test "#update should require authentication" do
    endpoint

    patch feed_webhook_token_path(feed)

    assert_redirected_to new_session_path
  end

  test "#update should require ownership" do
    endpoint
    sign_in_as(create(:user))

    patch feed_webhook_token_path(feed)

    assert_response :not_found
  end

  test "#update should answer not_found for a feed without an endpoint" do
    pull_feed = create(:feed, user: user)
    sign_in_as(user)

    patch feed_webhook_token_path(pull_feed)

    assert_response :not_found
  end
end
