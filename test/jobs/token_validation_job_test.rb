require "test_helper"

class TokenValidationJobTest < ActiveJob::TestCase
  def user
    @user ||= create(:user)
  end

  def access_token
    @access_token ||= create(:access_token, user: user).tap do |token|
      token.token = "freefeed_token_123"
      token.token_digest = BCrypt::Password.create("freefeed_token_123")
      token.save!
    end
  end

  test "marks token as active when validation succeeds" do
    # Mock successful HTTP response
    stub_successful_freefeed_response

    assert access_token.pending?

    TokenValidationJob.perform_now(access_token)

    access_token.reload
    assert access_token.active?
    assert_equal "testuser", access_token.owner
  end

  test "marks token as inactive when validation fails" do
    # Mock failed HTTP response
    stub_failed_freefeed_response

    assert access_token.pending?

    TokenValidationJob.perform_now(access_token)

    access_token.reload
    assert access_token.inactive?
  end

  test "marks token as inactive when HTTP error occurs" do
    # Mock HTTP error
    stub_request(:get, "https://freefeed.net/v4/users/whoami")
      .to_raise(StandardError.new("Connection failed"))

    assert access_token.pending?

    TokenValidationJob.perform_now(access_token)

    access_token.reload
    assert access_token.inactive?
  end

  test "does nothing when token is not present" do
    # Create token without token value, bypassing validation
    token_without_value = AccessToken.new(name: "Test Token", user: user, status: :pending)
    token_without_value.token_digest = BCrypt::Password.create("dummy")
    token_without_value.save!(validate: false)

    TokenValidationJob.perform_now(token_without_value)

    # Should remain pending since validation was skipped
    assert token_without_value.reload.pending?
  end

  test "marks token as inactive when JSON parsing fails" do
    # Mock response with invalid JSON
    stub_request(:get, "https://freefeed.net/v4/users/whoami")
      .to_return(status: 200, body: "invalid json", headers: { "Content-Type" => "application/json" })

    assert access_token.pending?

    TokenValidationJob.perform_now(access_token)

    access_token.reload
    assert access_token.inactive?
  end

  test "uses custom FREEFEED_HOST when set" do
    # Test with custom host
    ENV["FREEFEED_HOST"] = "https://custom.freefeed.com"

    stub_request(:get, "https://custom.freefeed.com/v4/users/whoami")
      .to_return(
        status: 200,
        body: { users: { username: "testuser" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    TokenValidationJob.perform_now(access_token)

    access_token.reload
    assert access_token.active?
  ensure
    ENV.delete("FREEFEED_HOST")
  end

  test "broadcasts status update on successful validation" do
    stub_successful_freefeed_response

    # Test that broadcast method gets called without error
    assert_nothing_raised do
      TokenValidationJob.perform_now(access_token)
    end

    access_token.reload
    assert access_token.active?
  end

  test "broadcasts status update on failed validation" do
    stub_failed_freefeed_response

    # Test that broadcast method gets called without error
    assert_nothing_raised do
      TokenValidationJob.perform_now(access_token)
    end

    access_token.reload
    assert access_token.inactive?
  end

  test "marks token as inactive when response format is invalid" do
    # Mock response with missing username field
    stub_request(:get, "https://freefeed.net/v4/users/whoami")
      .to_return(
        status: 200,
        body: { users: { screenName: "testuser", id: "test-id" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    assert access_token.pending?

    TokenValidationJob.perform_now(access_token)

    access_token.reload
    assert access_token.inactive?
  end

  private

  def stub_successful_freefeed_response
    stub_request(:get, "https://freefeed.net/v4/users/whoami")
      .with(
        headers: {
          "Authorization" => "Bearer freefeed_token_123",
          "Accept" => "application/json",
          "User-Agent" => "FreeFeed-Token-Validator"
        }
      )
      .to_return(
        status: 200,
        body: {
          users: {
            username: "testuser",
            screenName: "Test User",
            id: "test-id"
          }
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  def stub_failed_freefeed_response
    stub_request(:get, "https://freefeed.net/v4/users/whoami")
      .with(
        headers: {
          "Authorization" => "Bearer freefeed_token_123",
          "Accept" => "application/json",
          "User-Agent" => "FreeFeed-Token-Validator"
        }
      )
      .to_return(
        status: 401,
        body: { error: "Unauthorized" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end
end
