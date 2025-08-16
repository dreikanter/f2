require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "should get new" do
    get new_session_url
    assert_response :success
    assert_select "h4", "Sign In"
    assert_select "form input[name='email_address']"
    assert_select "form input[name='password']"
  end

  test "should create session with valid credentials" do
    user = users(:one)

    post session_url, params: { email_address: user.email_address, password: "password" }
    assert_redirected_to root_url
  end

  test "should not create session with invalid credentials" do
    post session_url, params: { email_address: "wrong@example.com", password: "wrong" }
    assert_redirected_to new_session_path
  end

  test "should destroy session" do
    user = users(:one)
    sign_in_as(user)

    delete session_url
    assert_redirected_to new_session_path
  end
end
