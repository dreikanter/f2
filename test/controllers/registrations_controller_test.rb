require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  def inviter
    @inviter ||= create(:user)
  end

  def invite
    @invite ||= create(:invite, created_by_user: inviter)
  end

  def used_invite
    @used_invite ||= create(:invite, created_by_user: inviter, invited_user: create(:user))
  end

  test "should redirect to root when no code provided" do
    get registration_url
    assert_redirected_to root_path
  end

  test "should redirect to root when invalid code provided" do
    get registration_url(code: "invalid-uuid")
    assert_redirected_to root_path
  end

  test "should show registration form with valid unused invite" do
    get registration_url(code: invite.id)
    assert_response :success
    assert_select "h1", "Create Your Account"
  end

  test "should show used invite message when invite is already used" do
    get registration_url(code: used_invite.id)
    assert_response :success
    assert_select ".alert-warning", /already been used/
  end

  test "should redirect to dashboard if already authenticated" do
    sign_in_as inviter
    get registration_url(code: invite.id)
    assert_redirected_to status_path
  end

  test "should create user with valid invite" do
    invite # Ensure invite is created before the assertion

    assert_difference("User.count", 1) do
      post registration_url, params: {
        code: invite.id,
        user: {
          name: "New User",
          email_address: "newuser@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end
    assert_redirected_to root_url

    invite.reload
    assert_not_nil invite.invited_user
    assert_equal "New User", invite.invited_user.name
  end

  test "should not create user with invalid invite code in create" do
    assert_no_difference("User.count") do
      post registration_url, params: {
        code: "invalid-uuid",
        user: {
          name: "New User",
          email_address: "newuser@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end
    assert_redirected_to root_path
  end

  test "should not create user with used invite" do
    used_invite # Ensure used_invite is created before the assertion

    assert_no_difference("User.count") do
      post registration_url, params: {
        code: used_invite.id,
        user: {
          name: "Another User",
          email_address: "another@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end
    assert_redirected_to root_path
  end

  test "should not create user without code parameter in create" do
    assert_no_difference("User.count") do
      post registration_url, params: {
        user: {
          name: "New User",
          email_address: "newuser@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end
    assert_redirected_to root_path
  end

  test "should show errors when user data is invalid" do
    invite # Ensure invite is created before the assertion

    assert_no_difference("User.count") do
      post registration_url, params: {
        code: invite.id,
        user: {
          name: "New User",
          email_address: "invalid",
          password: "short",
          password_confirmation: "short"
        }
      }
    end
    assert_response :unprocessable_entity
  end

  test "should redirect to dashboard if authenticated during create" do
    sign_in_as inviter
    assert_no_difference("User.count") do
      post registration_url, params: {
        code: invite.id,
        user: {
          name: "New User",
          email_address: "newuser@example.com",
          password: "password123",
          password_confirmation: "password123"
        }
      }
    end
    assert_redirected_to status_path
  end
end
