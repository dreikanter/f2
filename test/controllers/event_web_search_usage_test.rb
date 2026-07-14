require "test_helper"

class EventWebSearchUsageTest < ActionDispatch::IntegrationTest
  test "owner event page should show referenced search call count" do
    user = create(:user)
    credential = create(:search_credential, :active, user: user)
    feed = create(:feed, user: user)
    refresh_event = Event.create!(type: "feed_refresh", level: :info, subject: feed, user: user)
    2.times { WebSearchUsage.record!(credential: credential, refresh_event: refresh_event) }
    sign_in_as user

    get event_path(refresh_event)

    assert_response :success
    assert_select "[data-key='events.web_search_usage']"
    assert_select "[data-key='events.web_search_usage.calls.value']", text: "2"
  end

  test "owner event page should omit search usage without references" do
    user = create(:user)
    refresh_event = Event.create!(type: "feed_refresh", level: :info, user: user)
    sign_in_as user

    get event_path(refresh_event)

    assert_response :success
    assert_select "[data-key='events.web_search_usage']", count: 0
  end
end

class AdminEventWebSearchUsageTest < ActionDispatch::IntegrationTest
  test "admin event page should show referenced search call count" do
    admin = create(:user)
    create(:permission, user: admin, name: "admin")
    user = create(:user)
    credential = create(:search_credential, :active, user: user)
    feed = create(:feed, user: user)
    refresh_event = Event.create!(type: "feed_refresh", level: :info, subject: feed, user: user)
    3.times { WebSearchUsage.record!(credential: credential, refresh_event: refresh_event) }
    sign_in_as admin

    get admin_event_path(refresh_event)

    assert_response :success
    assert_select "[data-key='events.web_search_usage']"
    assert_select "[data-key='events.web_search_usage.calls.value']", text: "3"
  end
end
