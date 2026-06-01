require "test_helper"
require "view_component/test_case"

class Admin::UserInvitationsComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def stats
    @stats ||= UserStats.new(user)
  end

  def render_component
    render_inline(Admin::UserInvitationsComponent.new(user: user, stats: stats))
  end

  test "#call should render the invitation rows" do
    result = render_component

    assert_not_nil result.css('[data-key="invitations.available_invites"]').first
    assert_includes result.text, "Created Invites"
    assert_includes result.text, "Invited Users"
  end

  test "#call should render the available invites value and edit trigger" do
    result = render_component

    assert_not_nil result.css("#available-invites-value").first
    edit = result.css("a", text: "Edit").first
    assert_not_nil edit
    assert_equal "modal-trigger", edit["data-controller"]
  end
end
