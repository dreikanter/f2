require "test_helper"
require "view_component/test_case"

class Admin::UserDetailsComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def stats
    @stats ||= UserStats.new(user)
  end

  def render_component(target = user)
    render_inline(Admin::UserDetailsComponent.new(user: target, stats: UserStats.new(target)))
  end

  test "#call should render core user fields" do
    result = render_component

    assert_includes result.text, "Email"
    assert_includes result.text, user.email_address
    assert_includes result.text, "Created"
    assert_includes result.text, "Last Seen"
  end

  test "#call should show None when the user has no permissions" do
    result = render_component

    assert_includes result.text, "None"
  end

  test "#call should list permission display names when present" do
    create(:permission, user: user, name: "admin")
    result = render_component

    assert_includes result.text, "Admin"
  end

  test "#call should show Never when the user has never been seen" do
    result = render_component

    assert_includes result.text, "Never"
  end

  test "#call should show a Pending confirmation status for inactive users" do
    result = render_component(create(:user, :inactive))

    assert_equal "Pending confirmation", result.css('[data-key="user_details.status"]').text
  end

  test "#call should show an Active status for active users" do
    result = render_component(create(:user, state: :active))

    assert_equal "Active", result.css('[data-key="user_details.status"]').text
  end

  test "#call should show a Suspended status for suspended users" do
    result = render_component(create(:user, :suspended))

    assert_equal "Suspended", result.css('[data-key="user_details.status"]').text
  end
end
