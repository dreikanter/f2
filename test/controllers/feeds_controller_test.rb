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

  test "#create should be implemented" do
    skip "TODO: Implement feed creation"
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

  test "#update should be implemented" do
    skip "TODO: Implement feed update"
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
