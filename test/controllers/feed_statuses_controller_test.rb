require "test_helper"

class FeedStatusesControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user)
  end

  test "#update should enable feed when conditions are met" do
    sign_in_as(user)

    patch feed_status_path(feed), params: { status: "enabled" }

    assert_redirected_to feed
    follow_redirect!
    assert_includes response.body, "Feed enabled"

    feed.reload
    assert_equal "enabled", feed.state
  end

  test "#update should enable a ready draft feed" do
    sign_in_as(user)
    draft = create(:feed, :draft, user: user)

    patch feed_status_path(draft), params: { status: "enabled" }

    assert_redirected_to draft
    assert_equal "enabled", draft.reload.state
  end

  test "#update should disable feed" do
    sign_in_as(user)
    feed.update!(state: :enabled)

    patch feed_status_path(feed), params: { status: "disabled" }

    assert_redirected_to feed
    follow_redirect!
    assert_includes response.body, "Feed disabled"

    feed.reload
    assert_equal "disabled", feed.state
  end

  test "#update should record a feed_enabled event when enabling" do
    sign_in_as(user)

    assert_difference("Event.where(type: 'feed_enabled', subject: feed).count", 1) do
      patch feed_status_path(feed), params: { status: "enabled" }
    end
  end

  test "#update should record a warning feed_disabled event when disabling" do
    sign_in_as(user)
    feed.update!(state: :enabled)

    assert_difference("Event.where(type: 'feed_disabled', subject: feed).count", 1) do
      patch feed_status_path(feed), params: { status: "disabled" }
    end

    assert_equal "warning", Event.where(type: "feed_disabled", subject: feed).last.level
  end

  test "#update should respond with turbo stream when enabling" do
    sign_in_as(user)

    patch feed_status_path(feed), params: { status: "enabled" }, as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, ActionView::RecordIdentifier.dom_id(feed, :header)
    assert_includes response.body, ActionView::RecordIdentifier.dom_id(feed)
    assert_includes response.body, "Feed enabled"

    feed.reload
    assert_equal "enabled", feed.state
  end

  test "#update should respond with turbo stream when disabling" do
    sign_in_as(user)
    feed.update!(state: :enabled)

    patch feed_status_path(feed), params: { status: "disabled" }, as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, "Feed disabled"

    feed.reload
    assert_equal "disabled", feed.state
  end

  test "#update should respond with turbo stream when enablement fails" do
    sign_in_as(user)
    feed_without_token = create(:feed, :without_access_token, user: user)

    patch feed_status_path(feed_without_token), params: { status: "enabled" }, as: :turbo_stream

    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_includes response.body, "Cannot enable feed: missing"

    feed_without_token.reload
    assert_equal "disabled", feed_without_token.state
  end

  test "#update should reject an unsupported status" do
    sign_in_as(user)

    assert_raises(RuntimeError) do
      patch feed_status_path(feed), params: { status: "bogus" }
    end
  end

  test "#update should pause an enabled feed when status=disabled" do
    sign_in_as(user)
    enabled_feed = create(:feed, :enabled, user: user)

    patch feed_status_path(enabled_feed), params: { status: "disabled" }

    assert_redirected_to enabled_feed
    follow_redirect!
    assert_includes response.body, "Feed disabled"

    enabled_feed.reload
    assert_equal "disabled", enabled_feed.state
  end

  test "#update should re-enable a disabled feed when envelope is satisfied" do
    sign_in_as(user)
    disabled_feed = create(:feed, :disabled, user: user)

    patch feed_status_path(disabled_feed), params: { status: "enabled" }

    assert_redirected_to disabled_feed
    follow_redirect!
    assert_includes response.body, "Feed enabled"

    disabled_feed.reload
    assert_equal "enabled", disabled_feed.state
  end

  test "#update should not enable feed when access token is missing" do
    sign_in_as(user)
    feed_without_token = create(:feed, :without_access_token, user: user)

    patch feed_status_path(feed_without_token), params: { status: "enabled" }

    assert_redirected_to feed_without_token
    follow_redirect!
    assert_includes response.body, "Cannot enable feed: missing"

    feed_without_token.reload
    assert_equal "disabled", feed_without_token.state
  end

  test "#update should not enable feed when access token is inactive" do
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

  test "#update should not enable an AI feed without an AI credential" do
    sign_in_as(user)
    ai_feed = create(:feed, user: user, feed_profile_key: "llm", params: { "prompt" => "ruby news" })

    patch feed_status_path(ai_feed), params: { status: "enabled" }

    assert_redirected_to ai_feed
    follow_redirect!
    assert_includes response.body, "Cannot enable feed: missing active AI credential and AI model"

    ai_feed.reload
    assert_equal "disabled", ai_feed.state
  end

  test "#update should surface validation errors instead of raising when rules drift" do
    sign_in_as(user)
    feed.update_column(:params, {})

    patch feed_status_path(feed), params: { status: "enabled" }

    assert_redirected_to feed
    follow_redirect!
    assert_includes response.body, "Cannot enable feed: missing source"

    feed.reload
    assert_equal "disabled", feed.state
  end

  test "#update should redirect to login when not authenticated" do
    patch feed_status_path(feed), params: { status: "enabled" }
    assert_redirected_to new_session_url
  end

  test "#update should not allow access to other user's feeds" do
    sign_in_as(user)
    other_user = create(:user)
    other_feed = create(:feed, user: other_user)

    patch feed_status_path(other_feed), params: { status: "enabled" }
    assert_redirected_to feeds_path
    follow_redirect!
    assert_includes response.body, "Feed not found"
  end

  test "#update should handle concurrent modifications with optimistic locking" do
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
    assert_includes response.body, "Feed enabled"
  end

  test "#update should use database transaction for atomic updates" do
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

  test "#update should handle StaleObjectError gracefully" do
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
