require "test_helper"

module Admin
  class EventsListComponentTest < ViewComponent::TestCase
    def user
      @user ||= create(:user)
    end

    test "#call should render events as rows in the bordered list" do
      event = create(:event, type: "feed_refresh", user: user)

      result = render_inline(Admin::EventsListComponent.new(events: [event]))

      assert_not_nil result.at_css("ul[data-key='events.list'] > [data-event-id='#{event.id}']")
    end

    test "#call should link events to the operator-facing event page" do
      event = create(:event, user: user)

      result = render_inline(Admin::EventsListComponent.new(events: [event]))

      assert_not_nil result.at_css("a[href='#{Rails.application.routes.url_helpers.admin_event_path(event)}']")
    end

    test "#call should render the type/user/target footer rows" do
      feed = create(:feed, user: user)
      event = create(:event, type: "feed_refresh", subject: feed, user: user)

      result = render_inline(Admin::EventsListComponent.new(events: [event]))

      assert_not_nil result.at_css("[data-key='events.footer']")
      assert_not_nil result.at_css("[data-key='events.type']")
    end

    test "#call should expose the shared list DOM id" do
      event = create(:event, user: user)

      result = render_inline(Admin::EventsListComponent.new(events: [event], endpoint: "/admin/events"))

      assert_not_nil result.at_css("##{EventsListComponent::DOM_ID}[data-controller='polling']")
    end

    test "#call should render the empty state when there are no events" do
      result = render_inline(Admin::EventsListComponent.new(events: []))

      assert_not_nil result.at_css("[data-key='empty-state']")
      assert_empty result.css("li")
    end
  end
end
