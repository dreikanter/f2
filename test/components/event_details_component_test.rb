require "test_helper"
require "view_component/test_case"

class EventDetailsComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user, name: "Test Feed")
  end

  test ".for should return the base component" do
    event = create(:event, type: "generic_event")

    assert_instance_of EventDetailsComponent, EventDetailsComponent.for(event)
  end

  test "#call should render the created timestamp without admin extras" do
    event = create(:event, type: "owned_event", level: :warning, subject: feed)

    result = render_inline(EventDetailsComponent.for(event))

    assert_includes result.to_html, "Created"
    assert_empty result.css('[data-key="admin.event.user"]')
  end

  test "#call should render admin rows and links when admin" do
    event = create(:event, type: "owned_event", user: user, subject: feed)

    result = render_inline(EventDetailsComponent.for(event, admin: true))

    assert_equal "User ##{event.user_id}", result.css("a[data-key='admin.event.user']").text
  end
end
