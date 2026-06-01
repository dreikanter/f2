require "test_helper"
require "view_component/test_case"

class Admin::UserEmailStatusComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user).tap { |u| u.deactivate_email!(reason: "bounced") }
  end

  def render_component
    render_inline(Admin::UserEmailStatusComponent.new(user: user))
  end

  test "#call should show the deactivated status and reason" do
    result = render_component

    assert_includes result.text, "Deactivated"
    assert_includes result.text, "Bounced"
  end

  test "#call should offer reactivate and view-events actions" do
    result = render_component

    assert_includes result.text, "Reactivate Email"
    assert_includes result.text, "View Email Events"
  end
end
