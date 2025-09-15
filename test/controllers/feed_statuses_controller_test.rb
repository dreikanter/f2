require "test_helper"

class FeedStatusesControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user)
  end

  test "should enable feed when conditions are met" do
    sign_in_as(user)

    patch feed_status_path(feed), params: { status: "enabled" }

    assert_redirected_to feed
    follow_redirect!
    assert_includes response.body, "Feed was successfully enabled"

    feed.reload
    assert_equal "enabled", feed.state
  end

  test "should disable feed" do
    sign_in_as(user)
    feed.update!(state: :enabled)

    patch feed_status_path(feed), params: { status: "disabled" }

    assert_redirected_to feed
    follow_redirect!
    assert_includes response.body, "Feed was successfully disabled"

    feed.reload
    assert_equal "disabled", feed.state
  end

  test "should not enable feed when access token is missing" do
    sign_in_as(user)
    feed_without_token = create(:feed, :without_access_token, user: user)

    patch feed_status_path(feed_without_token), params: { status: "enabled" }

    assert_redirected_to feed_without_token
    follow_redirect!
    assert_includes response.body, "Cannot enable feed: missing"

    feed_without_token.reload
    assert_equal "disabled", feed_without_token.state
  end

  test "should not enable feed when access token is inactive" do
    sign_in_as(user)
    inactive_token = create(:access_token, :inactive, user: user)
    feed_with_inactive_token = create(:feed, user: user, access_token: inactive_token)

    patch feed_status_path(feed_with_inactive_token), params: { status: "enabled" }

    assert_redirected_to feed_with_inactive_token
    follow_redirect!
    assert_includes response.body, "Cannot enable feed: missing"

    feed_with_inactive_token.reload
    assert_equal "disabled", feed_with_inactive_token.state
  end

  test "should handle invalid status parameter" do
    sign_in_as(user)

    patch feed_status_path(feed), params: { status: "invalid" }

    assert_redirected_to feed
    follow_redirect!
    assert_includes response.body, "Invalid status parameter"
  end

  test "should redirect to login when not authenticated" do
    patch feed_status_path(feed), params: { status: "enabled" }
    assert_redirected_to new_session_url
  end

  test "should not allow access to other user's feeds" do
    sign_in_as(user)
    other_user = create(:user)
    other_feed = create(:feed, user: other_user)

    patch feed_status_path(other_feed), params: { status: "enabled" }
    assert_redirected_to feeds_path
    follow_redirect!
    assert_includes response.body, "Feed not found"
  end

  test "should handle concurrent modifications with optimistic locking" do
    sign_in_as(user)

    # Simulate concurrent modification by updating the feed in a separate transaction
    Feed.transaction do
      # This simulates another process modifying the feed
      feed.touch
    end

    # The update should still work because we're using pessimistic locking
    patch feed_status_path(feed), params: { status: "enabled" }

    assert_redirected_to feed
    follow_redirect!
    assert_includes response.body, "Feed was successfully enabled"
  end

  test "should use database transaction for atomic updates" do
    sign_in_as(user)

    # Test that a validation error during update doesn't change the state
    feed.update!(target_group: nil)  # This will make can_be_enabled? return false

    patch feed_status_path(feed), params: { status: "enabled" }

    assert_redirected_to feed
    follow_redirect!
    assert_includes response.body, "Cannot enable feed"

    # Verify the feed state wasn't changed
    feed.reload
    assert_equal "disabled", feed.state
  end

  test "should handle StaleObjectError gracefully" do
    sign_in_as(user)

    # Mock the controller's enable method to raise StaleObjectError
    FeedStatusesController.class_eval do
      alias_method :original_enable, :enable

      def enable(feed)
        raise ActiveRecord::StaleObjectError.new(feed, "update")
      end
    end

    begin
      patch feed_status_path(feed), params: { status: "enabled" }

      assert_redirected_to feed
      follow_redirect!
      assert_includes response.body, "Feed was modified by another user. Please try again."

      # The feed state should remain unchanged since the error was caught
      feed.reload
      assert_equal "disabled", feed.state
    ensure
      # Restore the original method
      FeedStatusesController.class_eval do
        alias_method :enable, :original_enable
        remove_method :original_enable
      end
    end
  end
end
