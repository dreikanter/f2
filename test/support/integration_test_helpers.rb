module IntegrationTestHelpers
  def sign_in_as(user)
    post session_url, params: { email_address: user.email_address, password: "password123" }
    follow_redirect!
  end
end
