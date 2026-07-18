require "test_helper"
require "view_component/test_case"

class EventDetailsComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def feed
    @feed ||= create(:feed, user: user, name: "Test Feed")
  end

  test "#call should render the created timestamp without admin extras" do
    event = create(:event, type: "owned_event", level: :warning, subject: feed)

    result = render_inline(EventDetailsComponent.new(event: event))

    assert_includes result.to_html, "Created"
    assert_empty result.css('[data-key="admin.event.user"]')
  end

  test "#call should render a compact user link when admin" do
    event = create(:event, type: "owned_event", user: user, subject: feed)

    result = render_inline(EventDetailsComponent.new(event: event, admin: true))
    link = result.css("a[data-key='admin.event.user']").first

    assert_equal event.user_id.to_s.last(5), link.text
    assert_equal "/admin/users/#{event.user_id}", link["href"]
    assert_equal "#{event.user_id} — #{user.email_address}", link["title"]
  end
end
