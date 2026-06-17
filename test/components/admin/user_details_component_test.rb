require "test_helper"
require "view_component/test_case"

class Admin::UserDetailsComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def stats
    @stats ||= UserStats.new(user)
  end

  def render_component
    render_inline(Admin::UserDetailsComponent.new(user: user, stats: stats))
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
end
