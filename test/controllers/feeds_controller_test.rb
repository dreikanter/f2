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

  test "#index should redirect to login when not authenticated" do
    get feeds_url
    assert_redirected_to new_session_path
  end

  test "#index should render feed list for authenticated user" do
    sign_in_as(user)
    feed
    get feeds_url
    assert_response :success
    assert_select "button[data-dropdown-toggle='feed-sort-menu']", 1
    assert_select "#feed-sort-menu a", 5
    assert_select "ul.divide-y li", minimum: 1
    assert_select "p", text: "You have 1 inactive feed"
  end

  test "#index should render tailwind pagination controls" do
    sign_in_as(user)
    create_list(:feed, 26, user: user)

    get feeds_url

    assert_response :success
    assert_select "nav[aria-label='Feeds pagination']"
    assert_select "nav[aria-label='Feeds pagination'] ul[class*='inline-flex']", minimum: 1
    assert_select "header p", text: /Showing/
  end

  test "#new should render when authenticated" do
    sign_in_as(user)
    get new_feed_url
    assert_response :success
  end

  test "#create should create feed when authenticated" do
    sign_in_as(user)

    assert_difference("Feed.count", 1) do
      post feeds_url, params: {
        feed: {
          name: "test-feed",
          url: "https://example.com/test.xml",
          cron_expression: "0 * * * *",
          feed_profile_key: "rss",
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

  test "#create should reject invalid data" do
    sign_in_as(user)

    assert_no_difference("Feed.count") do
      post feeds_url, params: {
        feed: {
          name: "Invalid Name With Spaces",
          url: "not-a-url",
          cron_expression: "",
          feed_profile_key: ""
        }
      }
    end

    assert_response :unprocessable_content
  end

  test "#show should render feed owned by user" do
    sign_in_as(user)
    get feed_url(feed)
    assert_response :success
    assert_includes response.body, feed.name
  end

  test "#show should return not found for other user's feed" do
    sign_in_as(user)
    get feed_url(other_feed)
    assert_response :not_found
  end

  test "#edit should render for own feed" do
    sign_in_as(user)
    get edit_feed_url(feed)
    assert_response :success
  end

  test "#edit should return not found for other user's feed" do
    sign_in_as(user)
    get edit_feed_url(other_feed)
    assert_response :not_found
  end

  test "#update should modify own feed" do
    sign_in_as(user)

    patch feed_url(feed, section: "content-source"), params: {
      feed: {
        name: "updated-feed"
      }
    }, as: :turbo_stream

    assert_response :success

    feed.reload
    assert_equal "updated-feed", feed.name
  end

  test "#update should reject invalid data" do
    sign_in_as(user)

    patch feed_url(feed, section: "content-source"), params: {
      feed: {
        url: "not-a-url"
      }
    }, as: :turbo_stream

    assert_response :success
    assert_includes response.body, "edit-form-container"

    feed.reload
    assert_equal "https://example.com/feed.xml", feed.url
  end

  test "#update should not modify other user's feed" do
    sign_in_as(user)

    patch feed_url(other_feed), params: {
      feed: { name: "hacked-feed" }
    }

    assert_response :not_found
  end

  test "#destroy should remove own feed" do
    sign_in_as(user)
    feed = create(:feed, user: user)

    assert_difference("Feed.count", -1) do
      delete feed_url(feed)
    end

    assert_redirected_to feeds_url
  end

  test "#destroy should not remove other user's feed" do
    sign_in_as(user)
    delete feed_url(other_feed)
    assert_response :not_found
  end

  test "#create should preserve name case" do
    sign_in_as(user)

    post feeds_url, params: {
      feed: {
        name: "Test-Feed",
        url: "https://example.com/test.xml",
        cron_expression: "0 * * * *",
        feed_profile_key: "rss",
        access_token_id: access_token.id
      }
    }

    feed = Feed.last

    assert_redirected_to feed_url(feed)
    assert_equal "Test-Feed", feed.name
  end

  test "#create should strip and normalize URLs" do
    sign_in_as(user)

    post feeds_url, params: {
      feed: {
        name: "test-feed",
        url: "  https://example.com/test.xml  ",
        cron_expression: "0 * * * *",
        feed_profile_key: "rss",
        access_token_id: access_token.id
      }
    }

    feed = Feed.last

    assert_redirected_to feed_url(feed)
    assert_equal "https://example.com/test.xml", feed.url
  end

  test "#create should normalize description by removing line breaks" do
    sign_in_as(user)

    post feeds_url, params: {
      feed: {
        name: "test-feed",
        url: "https://example.com/test.xml",
        cron_expression: "0 * * * *",
        feed_profile_key: "rss",
        description: "Line 1\nLine 2\r\nLine 3",
        access_token_id: access_token.id
      }
    }

    feed = Feed.last

    assert_redirected_to feed_url(feed)
    assert_equal "Line 1 Line 2 Line 3", feed.description
  end


  test "#create should handle simplified creation flow" do
    sign_in_as(user)

    assert_difference("Feed.count", 1) do
      post feeds_url, params: {
        feed: {
          name: "simple-feed",
          url: "https://example.com/test.xml",
          feed_profile_key: "rss"
        }
      }
    end

    feed = Feed.last
    assert_equal "simple-feed", feed.name
    assert_equal "disabled", feed.state
    assert_redirected_to feed_url(feed)
    assert_includes flash[:notice], "Feed was successfully created."
  end

  test "#show should render feed section" do
    sign_in_as(user)
    get feed_url(feed, section: "reposting"), as: :turbo_stream
    assert_response :success
    assert_match(/turbo-stream/, response.content_type)
  end

  test "#edit should render with section" do
    sign_in_as(user)
    get edit_feed_url(feed, section: "reposting"), as: :turbo_stream
    assert_response :success
    assert_match(/turbo-stream/, response.content_type)
  end

  test "#update should persist changes for section" do
    sign_in_as(user)

    patch feed_url(feed, section: "reposting"), params: {
      feed: {
        access_token_id: access_token.id,
        target_group: "testgroup"
      }
    }, as: :turbo_stream

    assert_response :success
    assert_match(/turbo-stream/, response.content_type)

    feed.reload
    assert_equal access_token, feed.access_token
    assert_equal "testgroup", feed.target_group
  end

  test "#update should refresh feed title when content-source section updates" do
    sign_in_as(user)

    patch feed_url(feed, section: "content-source"), params: {
      feed: {
        name: "updated-name",
        url: "https://updated.example.com/feed.xml"
      }
    }, as: :turbo_stream

    assert_response :success
    assert_includes response.body, "feed-title"

    feed.reload
    assert_equal "updated-name", feed.name
  end

  test "#update should handle failure with section" do
    sign_in_as(user)

    patch feed_url(feed, section: "reposting"), params: {
      feed: {
        target_group: "Invalid Group Name"
      }
    }, as: :turbo_stream

    assert_response :success
    assert_includes response.body, "edit-form-container"
  end

  test "#update should auto-disable enabled feed when configuration becomes invalid" do
    sign_in_as(user)
    enabled_feed = create(:feed, user: user, state: :enabled)

    patch feed_url(enabled_feed, section: "reposting"), params: {
      feed: {
        access_token_id: nil
      }
    }, as: :turbo_stream

    assert_response :success

    enabled_feed.reload
    assert_equal "disabled", enabled_feed.state
  end

  test "#update should clear access_token_id when no active tokens available" do
    sign_in_as(user)
    access_token.update!(status: :inactive)

    patch feed_url(feed, section: "reposting"), params: {
      feed: {
        access_token_id: access_token.id,
        target_group: "testgroup"
      }
    }, as: :turbo_stream

    assert_response :success
  end

  test "#update should render content_source_form template when content-source section has validation errors" do
    sign_in_as(user)

    patch feed_url(feed), params: {
      section: "content-source",
      feed: {
        name: "test",
        url: "invalid-url"
      }
    }, as: :turbo_stream

    assert_response :success
    assert_includes response.body, "Edit Source"
    assert_includes response.body, "must be a valid HTTP or HTTPS URL"
  end

  test "#index should sort feeds by name ascending" do
    sign_in_as(user)
    create(:feed, user: user, name: "Z Feed")
    create(:feed, user: user, name: "A Feed")

    get feeds_url(sort: "name", direction: "asc")
    assert_response :success

    response_body = response.body
    pos_a = response_body.index("A Feed")
    pos_z = response_body.index("Z Feed")
    assert pos_a < pos_z, "Expected A Feed to appear before Z Feed"
  end

  test "#index should sort feeds by name descending" do
    sign_in_as(user)
    create(:feed, user: user, name: "A Feed")
    create(:feed, user: user, name: "Z Feed")

    get feeds_url(sort: "name", direction: "desc")
    assert_response :success

    response_body = response.body
    pos_a = response_body.index("A Feed")
    pos_z = response_body.index("Z Feed")
    assert pos_z < pos_a, "Expected Z Feed to appear before A Feed"
  end

  test "#index should sort feeds by status" do
    sign_in_as(user)
    enabled_feed = create(:feed, :enabled, user: user, name: "Enabled Feed")
    disabled_feed = create(:feed, user: user, name: "Disabled Feed", state: :disabled)

    get feeds_url(sort: "status", direction: "asc")
    assert_response :success

    response_body = response.body
    pos_disabled = response_body.index("Disabled Feed")
    pos_enabled = response_body.index("Enabled Feed")
    assert pos_enabled < pos_disabled, "Expected enabled feed to appear before disabled feed"
  end

  test "#index should use default sort when no sort parameter provided" do
    sign_in_as(user)
    create(:feed, user: user, name: "Z Feed")
    create(:feed, user: user, name: "A Feed")

    get feeds_url
    assert_response :success

    response_body = response.body
    pos_a = response_body.index("A Feed")
    pos_z = response_body.index("Z Feed")
    assert pos_a < pos_z, "Expected A Feed to appear before Z Feed (default sort)"
  end

  test "#pagination should preserve sort parameters" do
    sign_in_as(user)
    3.times { |i| create(:feed, user: user, name: "Feed #{i}") }

    get feeds_url(sort: "name", direction: "desc", per_page: 2)
    assert_response :success
    assert_select "nav[aria-label='Feeds pagination'] a[href*='sort=name']"
    assert_select "nav[aria-label='Feeds pagination'] a[href*='direction=desc']"
  end
end
