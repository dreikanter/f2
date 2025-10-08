require "test_helper"

class AuthenticationTest < ActionDispatch::IntegrationTest
  test "authenticated? returns true when user is signed in" do
    user = create(:user)
    login_as(user)
    follow_redirect!

    get feeds_path
    assert_response :success
  end

  test "require_authentication redirects when not signed in" do
    get feeds_path
    assert_redirected_to new_session_path
  end

  test "update_session_activity touches session after 10 minutes" do
    user = create(:user)
    login_as(user)
    session = user.sessions.last

    session.update_column(:updated_at, 11.minutes.ago)

    get feeds_path
    assert_response :success

    assert session.reload.updated_at > 1.minute.ago
  end

  test "update_session_activity does not touch recent session" do
    user = create(:user)
    login_as(user)
    session = user.sessions.last

    session.update_column(:updated_at, 5.minutes.ago)
    old_timestamp = session.updated_at

    get feeds_path
    assert_response :success

    assert_equal old_timestamp.to_i, session.reload.updated_at.to_i
  end

  private

  def login_as(user)
    post session_url, params: { email_address: user.email_address, password: "password1234567890" }
  end
end
