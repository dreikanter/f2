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

  test "#call should link to invited users by name or email" do
    named_user = create(:user, name: "Named User")
    unnamed_user = create(:user, name: "", email_address: "unnamed@example.com")
    create(:invite, created_by_user: user, invited_user: named_user, created_at: 1.day.ago)
    create(:invite, created_by_user: user, invited_user: unnamed_user)

    result = render_component
    invited_users = result.css("dt").find { |item| item.text == "Invited Users" }.next_element

    assert_equal ["unnamed@example.com", "Named User"], invited_users.css("a").map(&:text)
    assert_equal ["/admin/users/#{unnamed_user.id}", "/admin/users/#{named_user.id}"], invited_users.css("a").map { _1["href"] }
  end
end
