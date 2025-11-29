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
    create_list(:feed, 4, user: user)

    get feeds_url, params: { per_page: 3 }

    assert_response :success
    assert_select "nav[aria-label='Feeds pagination']"
    assert_select "nav[aria-label='Feeds pagination'] ul[class*='inline-flex']", minimum: 1
    assert_select "div.text-center", text: /Showing/
  end

  test "#new should render when authenticated" do
    sign_in_as(user)
    get new_feed_url
    assert_response :success
  end

  test "#create should create feed with enabled state when enable_feed is checked" do
    sign_in_as(user)
    access_token

    feed_params = {
      url: "http://example.com/feed.xml",
      name: "Test Feed",
      feed_profile_key: "rss",
      access_token_id: access_token.id,
      target_group: "testgroup",
      schedule_interval: "1h"
    }

    assert_difference("Feed.count", 1) do
      post feeds_path, params: { feed: feed_params, enable_feed: "1" }
    end

    feed = Feed.last
    assert_equal "enabled", feed.state
    assert_not_nil feed.feed_schedule
    assert_not_nil feed.feed_schedule.next_run_at
    assert_not_nil feed.feed_schedule.last_run_at
    assert_redirected_to feed_path(feed)
    assert_match "successfully created and is now active", flash[:notice]
  end

  test "#create should create feed with disabled state when enable_feed is not checked" do
    sign_in_as(user)
    access_token

    feed_params = {
      url: "http://example.com/feed.xml",
      name: "Test Feed",
      feed_profile_key: "rss",
      access_token_id: access_token.id,
      target_group: "testgroup",
      schedule_interval: "1h"
    }

    assert_difference("Feed.count", 1) do
      post feeds_path, params: { feed: feed_params, enable_feed: "0" }
    end

    feed = Feed.last
    assert_equal "disabled", feed.state
    assert_redirected_to feed_path(feed)
    assert_match "currently disabled", flash[:notice]
  end

  test "#create should ignore state param and use enable_feed instead" do
    sign_in_as(user)
    access_token

    feed_params = {
      url: "http://example.com/feed.xml",
      name: "Test Feed",
      feed_profile_key: "rss",
      access_token_id: access_token.id,
      target_group: "testgroup",
      schedule_interval: "1h",
      state: "enabled"  # Attempt to bypass UI
    }

    assert_difference("Feed.count", 1) do
      post feeds_path, params: { feed: feed_params, enable_feed: "0" }
    end

    feed = Feed.last
    assert_equal "disabled", feed.state, "State should be disabled despite state param"
  end

  test "#create should render form with errors on validation failure" do
    sign_in_as(user)

    feed_params = {
      url: "invalid-url",
      name: "",
      feed_profile_key: "rss"
    }

    assert_no_difference("Feed.count") do
      post feeds_path, params: { feed: feed_params }
    end

    assert_response :unprocessable_entity
    assert_select "h1", text: "New Feed"
  end

  test "#create should render expanded form with preserved data on validation failure" do
    sign_in_as(user)
    access_token

    feed_params = {
      url: "http://example.com/feed.xml",
      name: "Test Feed",
      feed_profile_key: "rss",
      access_token_id: access_token.id,
      target_group: "",  # Missing required field
      schedule_interval: "1h"
    }

    assert_no_difference("Feed.count") do
      post feeds_path, params: { feed: feed_params, enable_feed: "1" }
    end

    assert_response :unprocessable_entity
    assert_select "h1", text: "New Feed"

    # Verify expanded form is shown, not collapsed form
    assert_select "input[name='feed[url_display]'][disabled]"
    assert_select "input[name='feed[name]'][value='Test Feed']"

    # Verify validation errors are shown
    assert_select "p.ff-form-error", text: /can't be blank|must be filled/
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

  test "#update should update feed with valid params" do
    sign_in_as(user)
    new_token = create(:access_token, user: user, host: "https://freefeed.net")

    patch feed_url(feed), params: {
      feed: {
        name: "Updated Feed Name",
        access_token_id: new_token.id,
        target_group: "new-group",
        schedule_interval: "2h"
      }
    }

    assert_redirected_to feed_path(feed)
    follow_redirect!
    assert_match "Feed 'Updated Feed Name' was successfully updated", response.body

    feed.reload
    assert_equal "Updated Feed Name", feed.name
    assert_equal new_token.id, feed.access_token_id
    assert_equal "new-group", feed.target_group
    assert_equal "2h", feed.schedule_interval
  end

  test "#update should show additional message for enabled feeds" do
    sign_in_as(user)
    enabled_feed = create(:feed, user: user, state: :enabled, access_token: access_token)

    patch feed_url(enabled_feed), params: {
      feed: {
        name: "Updated Active Feed",
        target_group: "updated-group"
      }
    }

    assert_redirected_to feed_path(enabled_feed)
    follow_redirect!
    assert_match "Changes will take effect on the next scheduled refresh", response.body
  end

  test "#update should render edit form with errors on validation failure" do
    sign_in_as(user)

    patch feed_url(feed), params: {
      feed: {
        name: "",
        url: "invalid-url"
      }
    }

    assert_response :unprocessable_entity
    assert_select "form"
  end

  test "#update should not allow changing url or feed_profile_key" do
    sign_in_as(user)
    original_url = feed.url
    original_profile = feed.feed_profile_key

    patch feed_url(feed), params: {
      feed: {
        url: "https://evil.com/feed.xml",
        feed_profile_key: "xkcd",
        name: "Updated Name"
      }
    }

    assert_redirected_to feed_path(feed)
    feed.reload
    assert_equal original_url, feed.url
    assert_equal original_profile, feed.feed_profile_key
    assert_equal "Updated Name", feed.name
  end

  test "#update should reset schedule next_run_at when interval changes" do
    sign_in_as(user)
    enabled_feed = create(:feed, user: user, state: :enabled, access_token: access_token)
    enabled_feed.create_feed_schedule!(next_run_at: 12.hours.from_now, last_run_at: Time.current)
    old_next_run = enabled_feed.feed_schedule.next_run_at

    patch feed_url(enabled_feed), params: {
      feed: {
        schedule_interval: "10m"
      }
    }

    assert_redirected_to feed_path(enabled_feed)
    enabled_feed.reload
    assert_equal "10m", enabled_feed.schedule_interval
    assert_operator enabled_feed.feed_schedule.next_run_at, :<, old_next_run
    assert_in_delta Time.current, enabled_feed.feed_schedule.next_run_at, 5.seconds
  end

  test "#update should not allow direct cron_expression updates" do
    sign_in_as(user)
    feed.update!(schedule_interval: "1h")
    original_cron = feed.cron_expression

    patch feed_url(feed), params: {
      feed: {
        cron_expression: "0 0 * * *",
        name: "Updated Name"
      }
    }

    assert_redirected_to feed_path(feed)
    feed.reload
    assert_equal original_cron, feed.cron_expression
    assert_equal "Updated Name", feed.name
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














  test "#index should sort feeds by name" do
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

  test "#pagination should preserve sort parameters" do
    sign_in_as(user)
    3.times { |i| create(:feed, user: user, name: "Feed #{i}") }

    get feeds_url(sort: "name", direction: "desc", per_page: 2)
    assert_response :success
    assert_select "nav[aria-label='Feeds pagination'] a[href*='sort=name']"
    assert_select "nav[aria-label='Feeds pagination'] a[href*='direction=desc']"
  end
end
