require "test_helper"

class InvitesControllerTest < ActionDispatch::IntegrationTest
  def user
    @user ||= create(:user, available_invites: 5)
  end

  def other_user
    @other_user ||= create(:user)
  end

  def invite
    @invite ||= create(:invite, created_by_user: user)
  end

  def used_invite
    @used_invite ||= create(:invite, created_by_user: user, invited_user: other_user)
  end

  test "should redirect to login when not authenticated" do
    get invites_url
    assert_redirected_to new_session_path
  end

  test "should get index when authenticated" do
    sign_in_as user
    get invites_url
    assert_response :success
    assert_select "nav[aria-label='Breadcrumb'] a[href=?]", settings_path, text: "Settings"
  end

  test "should show anonymized invited email for a used invite" do
    invited = create(:user, email_address: "invitee@example.com")
    create(:invite, created_by_user: user, invited_user: invited)
    sign_in_as user

    get invites_url

    assert_response :success
    assert_select '[data-key="invites.invited_email"]', text: "i...e@example.com"
  end

  test "should not render a copy button for a used invite" do
    invited = create(:user, email_address: "invitee@example.com")
    create(:invite, created_by_user: user, invited_user: invited)
    sign_in_as user

    get invites_url

    assert_select '[data-key="invites.copy"]', count: 0
  end

  test "should not list other users' invites for admin" do
    admin = create(:user).tap { |u| u.permissions.create!(name: "admin") }
    create(:invite, created_by_user: other_user, invited_user: admin)
    create(:invite, created_by_user: admin)
    sign_in_as admin

    get invites_url

    assert_response :success
    assert_select '[data-key="invites.card"]', count: 1
    assert_select '[data-key="invites.invited_email"]', count: 0
  end

  test "should render a copy button for an unused invite" do
    invite
    sign_in_as user

    get invites_url

    assert_select '[data-key="invites.copy"]'
  end

  test "should create invite when user has available invites" do
    sign_in_as user
    assert_difference("Invite.count", 1) do
      post invites_url
    end
    assert_response :success
  end

  test "should not create invite when user has no available invites" do
    u = create(:user, available_invites: 0)
    sign_in_as u
    # Policy will reject because create? checks available invites
    # This will raise Pundit::NotAuthorizedError which by default redirects to root
    post invites_url
    assert_redirected_to root_path
  end

  test "should not create more invites than available" do
    user.update!(available_invites: 1)
    sign_in_as user

    # First invite should succeed
    assert_difference("Invite.count", 1) do
      post invites_url
    end

    # Second invite should not be created
    assert_no_difference("Invite.count") do
      post invites_url
    end
  end

  test "should render enabled invite button when invites available" do
    sign_in_as user
    get invites_url
    assert_select "form[data-turbo-frame='_top'] button:not([disabled])[class*='hover:bg-surface-muted']"
  end

  test "should render disabled invite button when no invites available" do
    u = create(:user, available_invites: 0)
    sign_in_as u
    get invites_url
    assert_select "button[disabled]"
    assert_select "button[disabled][class*='opacity-50']"
  end

  test "should destroy own unused invite" do
    inv = invite # Create invite before signing in
    sign_in_as user
    assert_difference("Invite.count", -1) do
      delete invite_url(inv)
    end
    assert_response :success
  end

  test "should not destroy used invite" do
    inv = create(:invite, created_by_user: user, invited_user: other_user)
    sign_in_as user
    assert_no_difference("Invite.count") do
      delete invite_url(inv)
    end
  end

  test "should not destroy other user's invite" do
    u = user # Ensure user exists
    other_u = other_user # Ensure other_user exists
    other_invite = create(:invite, created_by_user: other_u)
    sign_in_as u

    # Should raise RecordNotFound because controller scopes to Current.user.created_invites
    delete invite_url(other_invite)
    # If no exception is raised, it means the invite was found and either deleted or rejected by policy
    # Let's check it wasn't deleted
    assert Invite.exists?(other_invite.id), "Other user's invite should not be deleted"
  end
end
