require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get new_password_url
    assert_response :success
  end

  test "should get edit with valid token" do
    user = users(:one)
    token = user.generate_token_for(:password_reset)

    get edit_password_url(token)
    assert_response :success
  end

  test "should send email for active user" do
    user = create(:user, state: :active)

    assert_enqueued_with(job: ActionMailer::MailDeliveryJob) do
      post passwords_url, params: { email_address: user.email_address }
    end

    assert_redirected_to new_session_path
  end

  test "should not send email for non-existent user" do
    post passwords_url, params: { email_address: "nonexistent@example.com" }
    assert_redirected_to new_session_path
  end

  test "should not send email for inactive user" do
    user = create(:user, state: :inactive)

    assert_no_enqueued_emails do
      post passwords_url, params: { email_address: user.email_address }
    end

    assert_redirected_to new_session_path
  end

  test "should update password with valid token" do
    user = users(:one)
    token = user.generate_token_for(:password_reset)

    put password_url(token), params: {
      password: "newpassword1234",
      password_confirmation: "newpassword1234"
    }

    assert_redirected_to new_session_path
    user.reload
    assert user.authenticate("newpassword1234")
  end

  test "should not update password with mismatched confirmation" do
    user = create(:user)
    token = user.generate_token_for(:password_reset)

    put password_url(token), params: {
      password: "newpassword",
      password_confirmation: "differentpassword"
    }

    assert_redirected_to edit_password_path(token)
    assert_equal "Passwords did not match.", flash[:alert]
  end

  test "should not update password with invalid token" do
    put password_url("invalid_token"), params: {
      password: "newpassword",
      password_confirmation: "newpassword"
    }

    assert_redirected_to new_password_path
  end
end
