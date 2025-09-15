require "test_helper"

class FeedsControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, :active, user: user)
  end

  def feed
    @feed ||= create(:feed, user: user)
  end

  def other_feed
    @other_feed ||= create(:feed, user: create(:user))
  end

  test "should redirect to login when not authenticated" do
    get feeds_url
    assert_redirected_to new_session_path
  end

  test "should get index when authenticated" do
    sign_in_as(user)
    get feeds_url
    assert_response :success
  end

  test "should get new when authenticated" do
    sign_in_as(user)
    get new_feed_url
    assert_response :success
  end

  test "should create feed when authenticated" do
    sign_in_as(user)

    assert_difference("Feed.count", 1) do
      post feeds_url, params: {
        feed: {
          name: "test-feed",
          url: "https://example.com/test.xml",
          cron_expression: "0 * * * *",
          loader: "http",
          processor: "rss",
          normalizer: "rss",
          description: "Test description",
          access_token_id: access_token.id
        }
      }
    end

    feed = Feed.last
    assert_equal user, feed.user
    assert_equal "test-feed", feed.name
    assert_equal "disabled", feed.state
    assert_redirected_to feed_url(feed)
  end

  test "should not create feed with invalid data" do
    sign_in_as(user)

    assert_no_difference("Feed.count") do
      post feeds_url, params: {
        feed: {
          name: "Invalid Name With Spaces",
          url: "not-a-url",
          cron_expression: "",
          loader: "",
          processor: "",
          normalizer: ""
        }
      }
    end

    assert_response :unprocessable_content
  end

  test "should show own feed" do
    sign_in_as(user)
    get feed_url(feed)
    assert_response :success
    assert_includes response.body, feed.name
  end

  test "should not show other user's feed" do
    sign_in_as(user)
    get feed_url(other_feed)
    assert_response :not_found
  end

  test "should get edit for own feed" do
    sign_in_as(user)
    get edit_feed_url(feed)
    assert_response :success
  end

  test "should not get edit for other user's feed" do
    sign_in_as(user)
    get edit_feed_url(other_feed)
    assert_response :not_found
  end

  test "should update own feed" do
    sign_in_as(user)

    patch feed_url(feed), params: {
      feed: {
        name: "updated-feed",
        description: "Updated description"
      }
    }

    assert_redirected_to feed_url(feed)

    feed.reload
    assert_equal "updated-feed", feed.name
    assert_equal "Updated description", feed.description
  end

  test "should not update feed with invalid data" do
    sign_in_as(user)

    patch feed_url(feed), params: {
      feed: {
        name: "Invalid Name",
        url: "not-a-url"
      }
    }

    assert_response :unprocessable_content

    feed.reload
    assert_not_equal "Invalid Name", feed.name
  end

  test "should not update other user's feed" do
    sign_in_as(user)

    patch feed_url(other_feed), params: {
      feed: { name: "hacked-feed" }
    }

    assert_response :not_found
  end

  test "should destroy own feed" do
    sign_in_as(user)
    feed = create(:feed, user: user)

    assert_difference("Feed.count", -1) do
      delete feed_url(feed)
    end

    assert_redirected_to feeds_url
  end

  test "should not destroy other user's feed" do
    sign_in_as(user)
    delete feed_url(other_feed)
    assert_response :not_found
  end

  test "should preserve name case" do
    sign_in_as(user)

    post feeds_url, params: {
      feed: {
        name: "Test-Feed",
        url: "https://example.com/test.xml",
        cron_expression: "0 * * * *",
        loader: "http",
        processor: "rss",
        normalizer: "rss",
        access_token_id: access_token.id
      }
    }

    feed = Feed.last

    assert_redirected_to feed_url(feed)
    assert_equal "Test-Feed", feed.name
  end

  test "should strip and normalize URLs" do
    sign_in_as(user)

    post feeds_url, params: {
      feed: {
        name: "test-feed",
        url: "  https://example.com/test.xml  ",
        cron_expression: "0 * * * *",
        loader: "http",
        processor: "rss",
        normalizer: "rss",
        access_token_id: access_token.id
      }
    }

    feed = Feed.last

    assert_redirected_to feed_url(feed)
    assert_equal "https://example.com/test.xml", feed.url
  end

  test "should normalize description by removing line breaks" do
    sign_in_as(user)

    post feeds_url, params: {
      feed: {
        name: "test-feed",
        url: "https://example.com/test.xml",
        cron_expression: "0 * * * *",
        loader: "http",
        processor: "rss",
        normalizer: "rss",
        description: "Line 1\nLine 2\r\nLine 3",
        access_token_id: access_token.id
      }
    }

    feed = Feed.last

    assert_redirected_to feed_url(feed)
    assert_equal "Line 1 Line 2 Line 3", feed.description
  end

  test "should create enabled feed when enabled checkbox is checked" do
    sign_in_as(user)

    post feeds_url, params: {
      feed: {
        name: "test-enabled-feed",
        url: "https://example.com/test.xml",
        cron_expression: "0 * * * *",
        loader: "http",
        processor: "rss",
        normalizer: "rss",
        access_token_id: access_token.id,
        target_group: "testgroup",
        state: "enabled"
      }
    }

    feed = Feed.last
    assert_equal "enabled", feed.state
  end

  test "should create disabled feed when enabled checkbox is unchecked" do
    sign_in_as(user)

    post feeds_url, params: {
      feed: {
        name: "test-disabled-feed",
        url: "https://example.com/test.xml",
        cron_expression: "0 * * * *",
        loader: "http",
        processor: "rss",
        normalizer: "rss",
        access_token_id: access_token.id,
        state: "disabled"
      }
    }

    feed = Feed.last
    assert_equal "disabled", feed.state
  end

  test "should update feed state when enabled checkbox changes" do
    sign_in_as(user)
    existing_feed = create(:feed, user: user, state: :enabled)

    patch feed_url(existing_feed), params: {
      feed: {
        state: "disabled"
      }
    }

    existing_feed.reload
    assert_equal "disabled", existing_feed.state
  end
end
