require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects with valid session" do
    user = create(:user)
    session = user.sessions.create!(user_agent: "test", ip_address: "127.0.0.1")
    
    cookies.signed[:session_id] = session.id
    
    connect
    
    assert_equal user, connection.current_user
  end

  test "rejects connection without valid session" do
    assert_reject_connection { connect }
  end
end