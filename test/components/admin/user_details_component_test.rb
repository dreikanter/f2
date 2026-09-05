require "test_helper"
require "view_component/test_case"

class Admin::UserDetailsComponentTest < ViewComponent::TestCase
  def user
    @user ||= create(:user)
  end

  def render_component(target = user)
    render_inline(Admin::UserDetailsComponent.new(user: target))
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

  test "#call should show historical activity without a session" do
    user.update!(last_seen_at: 45.days.ago)

    result = render_component

    last_seen = result.css("dt").find { |item| item.text == "Last Seen" }.next_element
    assert_equal user.last_seen_at.iso8601, last_seen.at_css("time")["datetime"]
  end

  test "#call should link to the user who sent the invitation" do
    inviter = create(:user, name: "Inviter")
    invited_user = create(:user)
    create(:invite, created_by_user: inviter, invited_user: invited_user)

    result = render_component(invited_user)

    assert_equal "Invited By", result.css("dt").last.text
    assert_equal "Inviter", result.css("dd").last.at_css("a").text
    assert_equal "/admin/users/#{inviter.id}", result.css("dd").last.at_css("a")["href"]
  end

  test "#call should identify an inviter with a blank name by email" do
    inviter = create(:user, name: "", email_address: "inviter@example.com")
    invited_user = create(:user)
    create(:invite, created_by_user: inviter, invited_user: invited_user)

    result = render_component(invited_user)

    assert_equal "inviter@example.com", result.css("dd").last.at_css("a").text
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
